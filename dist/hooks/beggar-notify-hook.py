#!/usr/bin/env python3
"""Beggar Hook 通知引擎 — 接收 stdin JSON，构建 markdown 消息并调用 notify.py"""
import sys, json, subprocess, os

def main():
    # 1. 安全解析 stdin JSON
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        return  # 空输入或非法 JSON → 静默退出

    event = payload.get("hook_event_name", "")
    cwd = payload.get("cwd", "")
    project = os.path.basename(cwd) if cwd else "unknown"

    # 3. 根据事件类型构建消息
    title, body = None, None

    if event == "Notification":
        ntype = payload.get("notification_type", "")
        if ntype == "permission_prompt":
            title = "🤖 流程卡点，需要您来确认"
            body = f"> **项目**：`{project}`\n> **详情**：{payload.get('message','')}\n\n请在 CodeBuddy 中确认操作"
        elif ntype == "idle_prompt":
            title = "⏳ CodeBuddy 等待您的输入"
            body = f"> **项目**：`{project}`\n\n已空闲超过 60 秒，请回到对话继续"

    elif event == "PreToolUse" and payload.get("tool_name") == "Bash":
        # 仅通知沙箱越权（dangerouslyDisableSandbox=true）场景
        # 这类命令必然需要用户确认，是真正的高危卡点
        ti = payload.get("tool_input", {})
        if ti.get("dangerouslyDisableSandbox") is True:
            cmd = (ti.get("command") or "")[:200]
            title = "⚠️ 沙箱越权命令，需要您来确认"
            body = f"> **项目**：`{project}`\n> **命令**：`{cmd}`\n\n此命令将在沙箱外执行，请在 CodeBuddy 中确认操作"

    if title is None:
        return

    # 4. 定位 notify 脚本
    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.dirname(os.path.dirname(script_dir))  # hooks/ → .codebuddy/ → /
    notify_dir = os.path.join(script_dir, "..", "skills", "beggar-notify")
    load_env = os.path.join(notify_dir, "load-env.sh")
    notify_py = os.path.join(notify_dir, "notify.py")
    if not os.path.exists(notify_py):
        return

    # 5. 加载环境变量（load-env.sh 使用相对路径，指定 cwd 为项目根）
    # Windows 兼容：检测 bash 路径，Git Bash 中 bash 通常可用
    bash_cmd = "bash"
    if sys.platform == "win32":
        for candidate in ["bash", "C:\\Program Files\\Git\\bin\\bash.exe", "C:\\Program Files\\Git\\usr\\bin\\bash.exe"]:
            try:
                subprocess.check_output([candidate, "--version"], stderr=subprocess.DEVNULL, timeout=3)
                bash_cmd = candidate
                break
            except Exception:
                continue
    try:
        out = subprocess.check_output(
            [bash_cmd, load_env], stderr=subprocess.DEVNULL, text=True, cwd=project_root, timeout=5
        )
    except Exception:
        return

    env = {}
    for line in out.strip().split("\n"):
        if line.startswith("export "):
            # load-env.sh 输出格式: export KEY="value"（由 json.dumps 生成，可靠）
            k, v = line[7:].split("=", 1)
            env[k] = v.strip("'\"")
    if not env.get("BEGGAR_NOTIFY_TOKEN"):
        return

    # 6. 发送通知
    # Windows 兼容：python3 在 Windows 上通常为 python
    py_cmd = "python3"
    if sys.platform == "win32":
        try:
            subprocess.check_output(["python3", "--version"], stderr=subprocess.DEVNULL, timeout=3)
        except Exception:
            py_cmd = "python"
    msg = f"### {title}\n\n{body}"
    try:
        subprocess.run([py_cmd, notify_py, msg], env={**os.environ, **env}, timeout=10)
    except Exception:
        pass  # 通知失败不阻塞 Hook

if __name__ == "__main__":
    main()
