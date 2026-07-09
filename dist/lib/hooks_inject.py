#!/usr/bin/env python3
"""
Beggar settings.json hooks injection utility.

Operates on CodeBuddy settings.json to manage superpowers plugin
and beggar notification/RTK hooks.

All paths are passed via environment variables:
  SETTINGS_FILE        - path to CodeBuddy settings.json
  HOOK_CMD             - full hook command string
  BEGGAR_GLOBAL        - "1" for global install, "0" for project install
  FIX_TARGET_PREFIX    - (optional) prefix for fixing hook paths

Actions (via ACTION env var):
  check                 - check if superpowers plugin is enabled
  inject_superpowers    - inject superpowers plugin config
  inject_hooks          - inject beggar hooks (Notification, PreToolUse, SubagentStop, RTK)
  fix_hooks             - detect and fix broken/old hook paths
  remove_hooks          - remove beggar hooks and superpowers plugin
  check_hooks_enabled   - check if beggar hooks are already configured
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile


def _get_settings_file():
    sf = os.environ.get('SETTINGS_FILE', '')
    if not sf:
        print('error: SETTINGS_FILE environment variable is required', file=sys.stderr)
        sys.exit(1)
    return sf


def _get_hook_cmd():
    explicit = os.environ.get('HOOK_CMD')
    if explicit:
        return explicit
    # Fallback when HOOK_CMD not provided by caller.
    # Shell-side (hooks.sh/init.sh) constructs hook_cmd with $PYTHON_CMD
    # and passes it via HOOK_CMD env var, so this fallback is rarely used.
    if os.environ.get('BEGGAR_GLOBAL') == '1':
        return 'test -f "${HOME}/.codebuddy/hooks/beggar-notify-hook.py" && python3 "${HOME}/.codebuddy/hooks/beggar-notify-hook.py" || exit 0'
    # Relative path: hook runs with CWD=project root, no env var dependency
    return 'test -f .codebuddy/hooks/beggar-notify-hook.py && python3 .codebuddy/hooks/beggar-notify-hook.py || exit 0'


def _get_fix_target_prefix():
    prefix = os.environ.get('FIX_TARGET_PREFIX', '')
    if prefix:
        return prefix
    if os.environ.get('BEGGAR_GLOBAL') == '1':
        return '$HOME/.codebuddy/hooks'
    return '$CODEBUDDY_PROJECT_DIR/.codebuddy/hooks'


def _load_settings(required=True):
    """Load settings.json, returns (data, file_exists)."""
    sf = _get_settings_file() if required else os.environ.get('SETTINGS_FILE', '')
    if not sf or not os.path.isfile(sf):
        return None, False
    with open(sf, 'r') as f:
        return json.load(f), True


def _save_settings(data):
    """Atomically write data to settings.json via temp file + rename."""
    sf = _get_settings_file()
    dir_name = os.path.dirname(sf)
    tmp = tempfile.NamedTemporaryFile(mode='w', dir=dir_name,
                                      prefix='.', suffix='.tmp', delete=False)
    try:
        json.dump(data, tmp, indent=2, ensure_ascii=False)
        tmp.flush()
        os.fsync(tmp.fileno())
    finally:
        tmp.close()
    os.replace(tmp.name, sf)


# ─── check ──────────────────────────────────────────────────────────────

def action_check():
    """Check if superpowers plugin is enabled. (setup.sh L1126-L1135)"""
    sf = os.environ.get('SETTINGS_FILE', '')
    if not sf or not os.path.isfile(sf):
        print('false')
        return
    try:
        with open(sf) as f:
            data = json.load(f)
        plugins = data.get('enabledPlugins', {})
        print('true' if plugins.get('superpowers@codebuddy-plugins-official', False) else 'false')
    except Exception:
        print('false')


# ─── inject_superpowers ─────────────────────────────────────────────────

def action_inject_superpowers():
    """Inject superpowers plugin into settings.json. (setup.sh L1153-L1167)"""
    sf = _get_settings_file()
    try:
        with open(sf, 'r') as f:
            data = json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        data = {}

    if 'enabledPlugins' not in data:
        data['enabledPlugins'] = {}
    data['enabledPlugins']['superpowers@codebuddy-plugins-official'] = True
    _save_settings(data)
    print('injected')


# ─── inject_hooks ───────────────────────────────────────────────────────

def action_inject_hooks():
    """Inject beggar hooks (Notification, PreToolUse, SubagentStop, RTK).
    (setup.sh L1356-L1458)

    Outputs one or more lines:
      injected           - hooks were written
      rtk_hook_injected  - RTK hook was added
      rtk_init_global    - rtk init -g succeeded
      rtk_not_found      - RTK binary not available
    """
    sf = _get_settings_file()
    hook_cmd = _get_hook_cmd()
    beg_global = os.environ.get('BEGGAR_GLOBAL', '0')

    data, _ = _load_settings()

    if 'hooks' not in data:
        data['hooks'] = {}
    hooks = data['hooks']

    # ── Notification hooks ──
    hooks['Notification'] = hooks.get('Notification', [])
    changed = False
    has_notify = any(
        'beggar-notify-hook.py' in h.get('command', '')
        for m in hooks['Notification'] if isinstance(m, dict)
        for h in m.get('hooks', [])
    )
    if not has_notify:
        hooks['Notification'].append({
            'matcher': 'permission_prompt',
            'hooks': [{'type': 'command', 'command': hook_cmd, 'timeout': 10}]
        })
        hooks['Notification'].append({
            'matcher': 'idle_prompt',
            'hooks': [{'type': 'command', 'command': hook_cmd, 'timeout': 10}]
        })
        changed = True

    # ── PreToolUse hooks ──
    hooks['PreToolUse'] = hooks.get('PreToolUse', [])

    # 5a: beggar notification hook for Bash
    has_bash_notify = any(
        'beggar-notify-hook.py' in h.get('command', '')
        for m in hooks['PreToolUse'] if isinstance(m, dict)
        for h in m.get('hooks', [])
    )
    if not has_bash_notify:
        hooks['PreToolUse'].append({
            'matcher': 'Bash',
            'hooks': [{'type': 'command', 'command': hook_cmd, 'timeout': 10}]
        })
        changed = True

    # 5b: RTK hook (if rtk is in PATH or common install locations)
    rtk_path = shutil.which('rtk')
    if not rtk_path:
        for candidate in [
            os.path.expanduser('~/.local/bin/rtk'),
            os.path.expanduser('~/.cargo/bin/rtk'),
            os.path.expanduser('~/bin/rtk'),
        ]:
            if os.path.isfile(candidate) and os.access(candidate, os.X_OK):
                rtk_path = candidate
                break
    if rtk_path:
        has_rtk = any(
            'rtk hook claude' in h.get('command', '')
            for m in hooks['PreToolUse'] if isinstance(m, dict)
            for h in m.get('hooks', [])
        )
        if not has_rtk:
            hooks['PreToolUse'].append({
                'matcher': 'Bash',
                'hooks': [{'type': 'command', 'command': 'rtk hook claude'}]
            })
            changed = True
            print('rtk_hook_injected')
        # Always ensure global RTK config is initialized
        try:
            subprocess.run([rtk_path, 'init', '-g'], capture_output=True, timeout=10)
            print('rtk_init_global')
        except Exception:
            pass
    else:
        print('rtk_not_found')

    # ── SubagentStop hooks ──
    hooks['SubagentStop'] = hooks.get('SubagentStop', [])
    has_stop = any(
        'beggar-notify-hook.py' in h.get('command', '')
        for m in hooks['SubagentStop'] if isinstance(m, dict)
        for h in m.get('hooks', [])
    )
    if not has_stop:
        hooks['SubagentStop'].append({
            'hooks': [{'type': 'command', 'command': hook_cmd, 'timeout': 10}]
        })
        changed = True

    if changed:
        _save_settings(data)
        print('injected')
    else:
        print('no_change')


# ─── fix_hooks ──────────────────────────────────────────────────────────

def action_fix_hooks():
    """Detect and fix broken/old hook paths in settings.json.
    (setup.sh L1205-L1247)

    Outputs:
      fixed            - paths were updated and saved
      no_fix_needed    - all paths are already correct
    """
    sf = _get_settings_file()
    fix_target_prefix = _get_fix_target_prefix()

    data, exists = _load_settings()
    if not exists:
        print('no_fix_needed')
        return

    hooks = data.get('hooks', {})
    fixed = False

    for event_name, matchers in hooks.items():
        for matcher in (matchers if isinstance(matchers, list) else []):
            for hook in matcher.get('hooks', []):
                cmd = hook.get('command', '')
                if 'beggar-notify-hook.py' not in cmd:
                    continue
                needs_fix = (
                    '$CODEBUDDY_PROJECT_DIR' in cmd
                    or '"/.codebuddy/hooks' in cmd
                    or ' /.codebuddy/hooks' in cmd
                    or ' \\.codebuddy/hooks' in cmd
                )
                if not needs_fix:
                    continue

                old_cmd = cmd
                # Fix 1: replace old project-relative prefix
                cmd = cmd.replace(
                    '$CODEBUDDY_PROJECT_DIR/.codebuddy/hooks',
                    fix_target_prefix
                )
                # Fix 2: absolute-root broken path with leading space
                if ' /.codebuddy/hooks/beggar-notify-hook.py' in cmd:
                    cmd = cmd.replace(
                        ' /.codebuddy/hooks/beggar-notify-hook.py',
                        ' "' + fix_target_prefix + '/beggar-notify-hook.py"'
                    )
                # Fix 3: doubly-quoted root path
                if '"/"/.codebuddy/hooks/beggar-notify-hook.py' in cmd:
                    cmd = cmd.replace(
                        '"/"/.codebuddy/hooks/beggar-notify-hook.py',
                        '"/"' + fix_target_prefix + '/beggar-notify-hook.py"'
                    )
                # Fix 4: escaped dot broken path
                if ' \\.codebuddy/hooks/beggar-notify-hook.py' in cmd:
                    cmd = cmd.replace(
                        ' \\.codebuddy/hooks/beggar-notify-hook.py',
                        ' "' + fix_target_prefix + '/beggar-notify-hook.py"'
                    )
                if cmd != old_cmd:
                    hook['command'] = cmd
                    fixed = True

    if fixed:
        _save_settings(data)
        print('fixed')
    else:
        print('no_fix_needed')


# ─── remove_hooks ───────────────────────────────────────────────────────

def action_remove_hooks():
    """Remove beggar hooks and superpowers plugin from settings.json.
    (setup.sh L2374-L2397)
    """
    sf = _get_settings_file()
    data, exists = _load_settings()
    if not exists:
        print('removed')
        return

    # Remove superpowers from enabledPlugins
    plugins = data.get('enabledPlugins', {})
    if 'superpowers@codebuddy-plugins-official' in plugins:
        del plugins['superpowers@codebuddy-plugins-official']
        if not plugins:
            del data['enabledPlugins']

    # Remove beggar hooks
    hooks = data.get('hooks', {})
    for event_name in list(hooks.keys()):
        matchers = hooks[event_name]
        if isinstance(matchers, list):
            filtered = []
            for m in matchers:
                if isinstance(m, dict):
                    hs = m.get('hooks', [])
                    has_beggar = any(
                        'beggar-notify-hook.py' in h.get('command', '')
                        for h in hs
                    )
                    if not has_beggar:
                        filtered.append(m)
            if filtered:
                hooks[event_name] = filtered
            else:
                del hooks[event_name]

    if not hooks:
        if 'hooks' in data:
            del data['hooks']

    _save_settings(data)
    print('removed')


# ─── check_hooks_enabled ────────────────────────────────────────────────

def action_check_hooks_enabled():
    """Check if beggar hooks are already configured.
    (setup.sh L1184-L1200)
    """
    sf = os.environ.get('SETTINGS_FILE', '')
    if not sf or not os.path.isfile(sf):
        print('false')
        return
    try:
        with open(sf) as f:
            data = json.load(f)
        hooks = data.get('hooks', {})
        for event_name, matchers in hooks.items():
            for matcher in (matchers if isinstance(matchers, list) else []):
                for hook in matcher.get('hooks', []):
                    if 'beggar-notify-hook.py' in hook.get('command', ''):
                        print('true')
                        return
        print('false')
    except Exception:
        print('false')


# ─── Dispatch ───────────────────────────────────────────────────────────

ACTIONS = {
    'check': action_check,
    'inject_superpowers': action_inject_superpowers,
    'inject_hooks': action_inject_hooks,
    'fix_hooks': action_fix_hooks,
    'remove_hooks': action_remove_hooks,
    'check_hooks_enabled': action_check_hooks_enabled,
}


def main():
    action = os.environ.get('ACTION', '')
    if not action:
        print('error: ACTION environment variable is required', file=sys.stderr)
        print('Valid actions: ' + ', '.join(sorted(ACTIONS.keys())), file=sys.stderr)
        sys.exit(1)

    handler = ACTIONS.get(action)
    if handler is None:
        print(f'error: unknown action: {action}', file=sys.stderr)
        print('Valid actions: ' + ', '.join(sorted(ACTIONS.keys())), file=sys.stderr)
        sys.exit(1)

    try:
        handler()
    except Exception as e:
        print(f'error: {e}', file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
