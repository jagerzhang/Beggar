#!/usr/bin/env python3
"""
Beggar Installer — Conversation-guided installation script.

This script is invoked by the beggar-install skill. It handles:
- Platform detection (CLI vs IDE)
- Download and extraction
- Platform-specific model fixes
- Installation verification

Usage:
    python3 install.py --detect --project-dir <dir>
    python3 install.py --detect-platform
    python3 install.py --download --project-dir <dir>
    python3 install.py --apply-fixes --project-dir <dir> --platform <cli|ide>
    python3 install.py --verify --project-dir <dir>
"""

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import urllib.request
import tarfile
from pathlib import Path

# Release download URL template
RELEASE_URL = "https://mirrors.tencent.com/repository/generic/npd-public/beggar/releases/v{version}/beggar-v{version}.tar.gz"
INSTALL_SH_URL = "https://mirrors.tencent.com/repository/generic/npd-public/beggar/install.sh"
LATEST_VERSION_URL = "https://mirrors.tencent.com/repository/generic/npd-public/beggar/latest-version.txt"


def run(cmd, cwd=None, capture=True):
    """Run a shell command."""
    kwargs = {"cwd": cwd, "shell": True}
    if capture:
        kwargs["capture_output"] = True
        kwargs["text"] = True
    try:
        result = subprocess.run(cmd, **kwargs)
        return result.returncode, result.stdout if capture else "", result.stderr if capture else ""
    except Exception as e:
        return 1, "", str(e)


def detect_state(project_dir):
    """Detect if Beggar is already installed in the project."""
    codebuddy_dir = Path(project_dir) / ".codebuddy"
    version_file = codebuddy_dir / "VERSION"
    setup_sh = codebuddy_dir / "setup.sh"

    state = {"installed": False, "version": None, "project_dir": str(Path(project_dir).resolve())}

    if setup_sh.exists():
        state["installed"] = True
        if version_file.exists():
            state["version"] = version_file.read_text().strip()

    return state


def detect_platform():
    """Detect whether running in CLI or IDE environment."""
    # 1. Strong IDE signals: specific env vars
    ide_env_vars = [
        "CODEBUDDY_IDE_VERSION", "CODEBUDDY_DESKTOP", "WORKBUDDY_IDE",
        "WORKBUDDY_DESKTOP", "WORKBUDDY_SESSION_ID", "CODEBUDDY_IDE",
        "VSCODE_PID", "VSCODE_CWD", "CURSOR_ENVIRONMENT",
        "ELECTRON_RUN_AS_NODE", "AGENT_ID", "AGENT_SESSION_ID"
    ]
    for var in ide_env_vars:
        if os.environ.get(var):
            return "ide"

    # 2. Check parent process chain for IDE indicators (Linux/macOS)
    try:
        pid = os.getppid()
        ide_processes = ["workbuddy", "codebuddy", "electron", "code", "cursor", "node"]
        while pid > 1:
            comm_path = f"/proc/{pid}/comm"
            if os.path.exists(comm_path):
                with open(comm_path) as f:
                    name = f.read().strip().lower()
                    if any(ide in name for ide in ide_processes):
                        return "ide"
            stat_path = f"/proc/{pid}/stat"
            if os.path.exists(stat_path):
                with open(stat_path) as f:
                    pid = int(f.read().split()[3])
            else:
                break
    except Exception:
        pass

    # 3. Check if stdin is NOT a TTY (IDE subprocesses often lack real TTY)
    if not sys.stdin.isatty():
        return "ide"

    # 4. CLI availability check — only meaningful if we have a real TTY
    ret, _, _ = run("which codebuddy 2>/dev/null || which cbc 2>/dev/null")
    if ret == 0:
        return "cli"

    # 5. No CLI found → likely IDE or restricted environment
    return "ide"


def get_latest_version():
    """Fetch the latest release version."""
    try:
        with urllib.request.urlopen(LATEST_VERSION_URL, timeout=10) as resp:
            return resp.read().decode().strip()
    except Exception:
        return None


def download_file(url, dest):
    """Download a file to destination."""
    try:
        urllib.request.urlretrieve(url, dest)
        return True
    except Exception as e:
        print(f"Download failed: {e}", file=sys.stderr)
        return False


def download_and_extract(project_dir, version=None):
    """Download the latest Beggar release and extract to .codebuddy/."""
    if version is None:
        version = get_latest_version()
        if version is None:
            print(json.dumps({"success": False, "error": "Failed to fetch latest version"}))
            return False

    project_path = Path(project_dir).resolve()
    codebuddy_dir = project_path / ".codebuddy"
    tmp_dir = project_path / ".beggar-tmp"
    tmp_dir.mkdir(exist_ok=True)

    tar_path = tmp_dir / f"beggar-v{version}.tar.gz"
    url = RELEASE_URL.format(version=version)

    print(f"Downloading Beggar v{version}...")
    if not download_file(url, tar_path):
        # Fallback: try curl
        ret, _, _ = run(f"curl -fsSL '{url}' -o '{tar_path}'")
        if ret != 0:
            print(json.dumps({"success": False, "error": f"Failed to download {url}"}))
            shutil.rmtree(tmp_dir, ignore_errors=True)
            return False

    extract_dir = tmp_dir / "extracted"
    extract_dir.mkdir(exist_ok=True)

    print(f"Extracting to {extract_dir}...")
    with tarfile.open(tar_path, "r:gz") as tf:
        tf.extractall(extract_dir)

    # Determine source directory within extracted archive
    # build-release.sh uses: cd dist/ && tar czf ...
    # So files are either directly in extract_dir/ or under a single wrapper dir
    if (extract_dir / "setup.sh").exists():
        src_dir = extract_dir
    elif (extract_dir / "dist" / "setup.sh").exists():
        src_dir = extract_dir / "dist"
    else:
        inner_dirs = [d for d in extract_dir.iterdir() if d.is_dir()]
        if inner_dirs and (inner_dirs[0] / "setup.sh").exists():
            src_dir = inner_dirs[0]
        else:
            print(json.dumps({"success": False, "error": "Invalid archive structure: setup.sh not found"}))
            shutil.rmtree(tmp_dir, ignore_errors=True)
            return False

    # Ensure .codebuddy/ exists
    codebuddy_dir.mkdir(exist_ok=True)

    # Incremental sync: copy files from src_dir to codebuddy_dir
    # Skip files that exist in codebuddy_dir but are NOT in src_dir (user custom files)
    added, updated, unchanged, preserved = 0, 0, 0, 0

    for src_file in src_dir.rglob("*"):
        if not src_file.is_file():
            continue
        rel_path = src_file.relative_to(src_dir)
        dest_file = codebuddy_dir / rel_path

        if dest_file.exists():
            # Compare SHA256
            with open(src_file, "rb") as f:
                src_hash = hashlib.sha256(f.read()).hexdigest()
            with open(dest_file, "rb") as f:
                dest_hash = hashlib.sha256(f.read()).hexdigest()
            if src_hash == dest_hash:
                unchanged += 1
            else:
                dest_file.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(src_file, dest_file)
                updated += 1
        else:
            dest_file.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src_file, dest_file)
            added += 1

    # Preserve files in codebuddy_dir that don't exist in src_dir (user customizations)
    # BUT delete beggar-managed files that are no longer in the release (e.g. old rtk binaries)
    removed = 0
    for dest_file in codebuddy_dir.rglob("*"):
        if not dest_file.is_file():
            continue
        rel_path = dest_file.relative_to(codebuddy_dir)
        src_file = src_dir / rel_path
        if not src_file.exists():
            # Check if this is a beggar-managed file that should be cleaned up
            rel_str = str(rel_path)
            is_beggar_managed = False
            # Old rtk binaries
            if rel_str.startswith("tools/rtk-"):
                is_beggar_managed = True
            # Old beggar-managed skill/command files (user custom files are in local/, memory/)
            if rel_str.startswith(("skills/", "commands/", "agents/", "rules/")):
                is_beggar_managed = True
            if is_beggar_managed:
                try:
                    dest_file.unlink()
                    removed += 1
                except Exception:
                    pass
            else:
                preserved += 1

    # Clean up empty directories left after deletion
    for subdir in sorted(codebuddy_dir.rglob("*"), key=lambda p: len(str(p)), reverse=True):
        if subdir.is_dir() and subdir != codebuddy_dir:
            try:
                if not any(subdir.iterdir()):
                    subdir.rmdir()
            except Exception:
                pass

    shutil.rmtree(tmp_dir, ignore_errors=True)

    print(json.dumps({
        "success": True,
        "version": version,
        "added": added,
        "updated": updated,
        "unchanged": unchanged,
        "preserved": preserved,
        "removed": removed,
    }))
    return True


def apply_platform_fixes(project_dir, platform):
    """Apply platform-specific fixes (marker file only)."""
    codebuddy_dir = Path(project_dir) / ".codebuddy"

    # Write platform marker
    marker_file = codebuddy_dir / ".beggar-platform"
    marker_file.write_text(platform)

    return True


def verify_installation(project_dir):
    """Verify that Beggar is correctly installed."""
    codebuddy_dir = Path(project_dir) / ".codebuddy"
    errors = []

    # Check required files
    required_files = [
        "setup.sh", "VERSION", "models.json",
        "agents/architect.md", "agents/coder-senior.md", "agents/coder-standard.md",
        "agents/coder-lite.md", "agents/reviewer.md", "agents/reviewer-b.md",
        "agents/tester.md", "agents/recorder.md", "agents/goal-evaluator.md",
        "skills/beggar-workflow/SKILL.md",
    ]
    for rel_path in required_files:
        if not (codebuddy_dir / rel_path).exists():
            errors.append(f"Missing: {rel_path}")

    # Check models.json validity
    models_json = codebuddy_dir / "models.json"
    if models_json.exists():
        try:
            with open(models_json) as f:
                json.load(f)
        except json.JSONDecodeError as e:
            errors.append(f"Invalid models.json: {e}")

    # Check platform marker
    marker = codebuddy_dir / ".beggar-platform"
    platform = marker.read_text().strip() if marker.exists() else "unknown"

    # Check subagent_type references in SKILL.md
    skill_md = codebuddy_dir / "skills/beggar-workflow/SKILL.md"
    has_subagent = False
    if skill_md.exists():
        content = skill_md.read_text()
        has_subagent = "subagent_type" in content
    if not has_subagent:
        errors.append("SKILL.md missing subagent_type references")

    result = {
        "success": len(errors) == 0,
        "platform": platform,
        "errors": errors,
    }
    print(json.dumps(result))
    return len(errors) == 0


def main():
    parser = argparse.ArgumentParser(description="Beggar Installer")
    parser.add_argument("--project-dir", default=".", help="Target project directory")
    parser.add_argument("--detect", action="store_true", help="Detect installation state")
    parser.add_argument("--detect-platform", action="store_true", help="Detect CLI vs IDE")
    parser.add_argument("--download", action="store_true", help="Download and extract latest version")
    parser.add_argument("--apply-fixes", action="store_true", help="Apply platform-specific fixes")
    parser.add_argument("--platform", choices=["cli", "ide"], help="Platform type for fixes")
    parser.add_argument("--verify", action="store_true", help="Verify installation")
    parser.add_argument("--version", help="Specific version to download")

    args = parser.parse_args()

    if args.detect:
        state = detect_state(args.project_dir)
        print(json.dumps(state))
        return 0

    if args.detect_platform:
        platform = detect_platform()
        print(json.dumps({"platform": platform}))
        return 0

    if args.download:
        ok = download_and_extract(args.project_dir, args.version)
        return 0 if ok else 1

    if args.apply_fixes:
        if not args.platform:
            print(json.dumps({"success": False, "error": "--platform required"}))
            return 1
        ok = apply_platform_fixes(args.project_dir, args.platform)
        print(json.dumps({"success": ok}))
        return 0 if ok else 1

    if args.verify:
        ok = verify_installation(args.project_dir)
        return 0 if ok else 1

    parser.print_help()
    return 1


if __name__ == "__main__":
    sys.exit(main())
