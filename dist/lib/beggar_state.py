#!/usr/bin/env python3
"""beggar-state: 状态文件管理工具

封装 beggar workflow 中所有固定状态操作，减少 Leader token 消耗。

子命令:
  init        初始化 goal-state.json
  set         设置单个字段
  get         读取单个字段
  post-call   Agent 调用后置位（递增计数 + 设置锁 + 追加日志）
  check       安全边界检查
  reset       重置单轮状态锁
  step        更新 current_step
  achieve     标记目标达成
  dispatch    追加 agent_dispatch.log
  find        查找活跃状态文件
"""
import json
import os
import sys
import argparse
from datetime import datetime, timezone


def find_state_file(mode="auto"):
    """查找活跃的状态文件。
    mode: auto / goal / start
    返回 (path, type) 或 (None, None)
    """
    openspec_dir = os.path.join(os.getcwd(), "openspec", "changes")
    if not os.path.isdir(openspec_dir):
        return None, None

    if mode in ("auto", "goal"):
        fallback = None
        for d in sorted(os.listdir(openspec_dir)):
            goal_dir = os.path.join(openspec_dir, d)
            if not os.path.isdir(goal_dir):
                continue
            state_path = os.path.join(goal_dir, "goal-state.json")
            if os.path.isfile(state_path):
                try:
                    with open(state_path) as f:
                        data = json.load(f)
                    if data.get("status") == "in_progress":
                        return state_path, "goal"
                    if fallback is None:
                        fallback = (state_path, "goal")
                except (json.JSONDecodeError, IOError):
                    continue
        if fallback:
            return fallback

    if mode in ("auto", "start"):
        for d in sorted(os.listdir(openspec_dir)):
            change_dir = os.path.join(openspec_dir, d)
            if not os.path.isdir(change_dir):
                continue
            state_path = os.path.join(change_dir, "start-state.json")
            if os.path.isfile(state_path):
                try:
                    with open(state_path) as f:
                        data = json.load(f)
                    if data.get("current_step") not in (None, "", "archived"):
                        return state_path, "start"
                except (json.JSONDecodeError, IOError):
                    continue

    return None, None


def get_state_path(explicit_path=None, mode="auto"):
    """获取状态文件路径，优先使用显式指定路径"""
    if explicit_path:
        return explicit_path, "goal" if "goal-state" in explicit_path else "start"
    path, stype = find_state_file(mode)
    if not path:
        print(json.dumps({"error": "未找到活跃的状态文件", "hint": "请确认在项目根目录执行，且 openspec/changes/ 下存在 in_progress 的 state 文件"}), file=sys.stderr)
        sys.exit(1)
    return path, stype


def load_state(path):
    try:
        with open(path) as f:
            return json.load(f)
    except json.JSONDecodeError as e:
        print(json.dumps({"error": f"状态文件 JSON 格式错误: {e}"}), file=sys.stderr)
        sys.exit(1)
    except FileNotFoundError:
        print(json.dumps({"error": f"状态文件不存在: {path}"}), file=sys.stderr)
        sys.exit(1)


def save_state(path, data):
    data["updated_at"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    with open(path, "w") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")


def now_iso():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def change_dir_from_state(state_path):
    """从状态文件路径推导 change 目录"""
    return os.path.dirname(state_path)


# ─── subcommands ─────────────────────────────────────────────

def cmd_init(args):
    """初始化 goal-state.json"""
    target_dir = args.target_dir
    if not target_dir:
        # 默认 goal-pending 目录
        target_dir = os.path.join(os.getcwd(), "openspec", "changes", "goal-pending")
    os.makedirs(target_dir, exist_ok=True)
    state_path = os.path.join(target_dir, "goal-state.json")

    if os.path.exists(state_path) and not args.force:
        print(json.dumps({"status": "exists", "path": state_path, "hint": "使用 --force 覆盖"}))
        return

    now = now_iso()
    data = {
        "goal": args.goal or "",
        "status": "in_progress",
        "current_step": args.step or "0.1-clarification",
        "current_iteration": 0,
        "max_iterations": args.max_iterations or 8,
        "max_agent_calls": args.max_agent_calls or 80,
        "agent_calls_used": 0,
        "no_progress_streak": 0,
        "no_progress_limit": args.no_progress_limit or 3,
        "design_revisions_used": 0,
        "human_reject_count": 0,
        "human_reject_limit": args.human_reject_limit or 3,
        "completed_steps": [],
        "director_final_review": args.director_final_review or False,
        "director_target_review_done": False,
        "director_dispute_review_done": False,
        "director_dispute_verdict": None,
        "director_final_review_done": False,
        "human_director_done": False,
        "human_director_verdict": None,
        "evaluator_done": False,
        "evaluator_verdict": None,
        "evaluator_confidence": None,
        "evaluator_reason": None,
        "stop_after_turns": args.stop_after_turns or None,
        "stop_after_minutes": args.stop_after_minutes or None,
        "verification_results": [],
        "created_at": now,
        "updated_at": now,
    }
    save_state(state_path, data)
    print(json.dumps({"status": "created", "path": state_path}, ensure_ascii=False))


def cmd_set(args):
    """设置单个字段"""
    path, _ = get_state_path(args.state_file, args.mode)
    data = load_state(path)

    # 尝试解析 JSON 值（支持 bool/int/float/string/JSON array/object）
    value = args.value
    if value.lower() == "true":
        value = True
    elif value.lower() == "false":
        value = False
    elif value.lower() == "null":
        value = None
    elif value.startswith("[") or value.startswith("{"):
        try:
            value = json.loads(value)
        except json.JSONDecodeError as e:
            print(json.dumps({"error": f"JSON 解析失败: {e}"}), file=sys.stderr)
            sys.exit(1)
    else:
        try:
            value = int(value)
        except ValueError:
            try:
                value = float(value)
            except ValueError:
                pass  # 保持字符串

    data[args.field] = value
    save_state(path, data)
    print(json.dumps({"status": "ok", "field": args.field, "value": value, "path": path}, ensure_ascii=False))


def cmd_get(args):
    """读取单个字段"""
    path, _ = get_state_path(args.state_file, args.mode)
    data = load_state(path)
    value = data.get(args.field)
    print(json.dumps({"field": args.field, "value": value}, ensure_ascii=False))


def cmd_post_call(args):
    """Agent 调用后置位：递增 agent_calls_used + 设置锁 + 追加 dispatch log"""
    path, _ = get_state_path(args.state_file, args.mode)
    data = load_state(path)

    # 递增 agent_calls_used
    data["agent_calls_used"] = data.get("agent_calls_used", 0) + 1

    # 设置状态锁字段
    locks_set = []
    if args.lock:
        data[args.lock] = True
        locks_set.append(args.lock)

    # 写入额外字段（JSON 格式）
    extras_set = []
    if args.extra:
        try:
            extras = json.loads(args.extra)
            for k, v in extras.items():
                data[k] = v
                extras_set.append(k)
        except json.JSONDecodeError as e:
            print(json.dumps({"error": f"--extra JSON 解析失败: {e}"}), file=sys.stderr)
            sys.exit(1)

    # 追加 completed_steps
    if args.step_id and args.step_id not in data.get("completed_steps", []):
        data.setdefault("completed_steps", []).append(args.step_id)

    # 追加 agent_dispatch.log
    change_dir = change_dir_from_state(path)
    log_path = os.path.join(change_dir, "agent_dispatch.log")
    log_entry = {
        "step": args.step or "",
        "agent_type": args.agent or "",
        "task": args.task or "",
        "ts": now_iso(),
    }
    with open(log_path, "a") as f:
        f.write(json.dumps(log_entry, ensure_ascii=False) + "\n")

    save_state(path, data)
    print(json.dumps({
        "status": "ok",
        "agent_calls_used": data["agent_calls_used"],
        "locks_set": locks_set,
        "extras_set": extras_set,
        "step_id_added": args.step_id or None,
        "dispatch_log": log_path,
    }, ensure_ascii=False))


def cmd_check(args):
    """安全边界检查"""
    path, _ = get_state_path(args.state_file, args.mode)
    data = load_state(path)

    results = []
    should_pause = False

    # 1. max_iterations
    max_iter = data.get("max_iterations", 8)
    cur_iter = data.get("current_iteration", 0)
    if cur_iter >= max_iter:
        results.append({"check": "max_iterations", "passed": False, "detail": f"{cur_iter} >= {max_iter}", "action": "暂停，向用户报告进展"})
        should_pause = True
    else:
        results.append({"check": "max_iterations", "passed": True, "detail": f"{cur_iter}/{max_iter}"})

    # 2. max_agent_calls
    max_calls = data.get("max_agent_calls", 80)
    calls_used = data.get("agent_calls_used", 0)
    if calls_used >= max_calls:
        results.append({"check": "max_agent_calls", "passed": False, "detail": f"{calls_used} >= {max_calls}", "action": "暂停，向用户报告预算消耗"})
        should_pause = True
    else:
        results.append({"check": "max_agent_calls", "passed": True, "detail": f"{calls_used}/{max_calls}"})

    # 3. no_progress_streak
    no_prog_limit = data.get("no_progress_limit", 3)
    no_prog = data.get("no_progress_streak", 0)
    if no_prog >= no_prog_limit:
        results.append({"check": "no_progress_streak", "passed": False, "detail": f"{no_prog} >= {no_prog_limit}", "action": "暂停，向用户报告阻塞点"})
        should_pause = True
    else:
        results.append({"check": "no_progress_streak", "passed": True, "detail": f"{no_prog}/{no_prog_limit}"})

    # 4. stop_after_turns
    stop_turns = data.get("stop_after_turns")
    if stop_turns is not None and cur_iter >= stop_turns:
        results.append({"check": "stop_after_turns", "passed": False, "detail": f"{cur_iter} >= {stop_turns}", "action": "暂停，向用户报告轮次上限"})
        should_pause = True
    elif stop_turns is not None:
        results.append({"check": "stop_after_turns", "passed": True, "detail": f"{cur_iter}/{stop_turns}"})

    # 5. stop_after_minutes
    stop_mins = data.get("stop_after_minutes")
    if stop_mins is not None:
        created_at = data.get("created_at", "")
        if created_at:
            try:
                created = datetime.fromisoformat(created_at.replace("Z", "+00:00"))
                elapsed = (datetime.now(timezone.utc) - created).total_seconds() / 60
                if elapsed >= stop_mins:
                    results.append({"check": "stop_after_minutes", "passed": False, "detail": f"{elapsed:.0f}min >= {stop_mins}min", "action": "暂停，向用户报告时间上限"})
                    should_pause = True
                else:
                    results.append({"check": "stop_after_minutes", "passed": True, "detail": f"{elapsed:.0f}/{stop_mins}min"})
            except (ValueError, TypeError):
                results.append({"check": "stop_after_minutes", "passed": True, "detail": f"created_at 解析失败，跳过"})

    # 6. human_reject_count
    reject_count = data.get("human_reject_count", 0)
    reject_limit = data.get("human_reject_limit", 3)
    if reject_count >= reject_limit:
        results.append({"check": "human_reject_count", "passed": False, "detail": f"{reject_count} >= {reject_limit}", "action": "强制触发 Director 介入（不暂停）"})
    else:
        results.append({"check": "human_reject_count", "passed": True, "detail": f"{reject_count}/{reject_limit}"})

    print(json.dumps({
        "should_pause": should_pause,
        "results": results,
    }, ensure_ascii=False))

    if should_pause:
        sys.exit(2)  # 非零退出码提示 Leader 需要暂停


def cmd_reset(args):
    """重置单轮状态锁"""
    path, _ = get_state_path(args.state_file, args.mode)
    data = load_state(path)

    # 递增 current_iteration
    data["current_iteration"] = data.get("current_iteration", 0) + 1

    # 重置单轮状态锁（reset_values 同时用于实际重置和输出报告）
    reset_values = {
        "director_dispute_review_done": False,
        "director_dispute_verdict": None,
        "director_final_review_done": False,
        "evaluator_done": False,
        "evaluator_verdict": None,
        "evaluator_confidence": None,
        "evaluator_reason": None,
        "human_director_done": False,
        "human_director_verdict": None,
    }

    for field, value in reset_values.items():
        data[field] = value

    # 清空 completed_steps
    data["completed_steps"] = []

    # director_target_review_done 保持 true（不重置）
    # human_reject_count 不重置

    save_state(path, data)
    print(json.dumps({
        "status": "ok",
        "current_iteration": data["current_iteration"],
        "reset_fields": list(reset_values.keys()),
        "kept_fields": ["director_target_review_done", "human_reject_count"],
    }, ensure_ascii=False))


def cmd_step(args):
    """更新 current_step"""
    path, _ = get_state_path(args.state_file, args.mode)
    data = load_state(path)
    data["current_step"] = args.step
    save_state(path, data)
    print(json.dumps({"status": "ok", "current_step": args.step, "path": path}, ensure_ascii=False))


def cmd_achieve(args):
    """标记目标达成"""
    path, _ = get_state_path(args.state_file, args.mode)
    data = load_state(path)
    data["status"] = "achieved"
    data["current_step"] = "achieved"
    save_state(path, data)
    print(json.dumps({"status": "achieved", "path": path}, ensure_ascii=False))


def cmd_dispatch(args):
    """追加 agent_dispatch.log"""
    path, _ = get_state_path(args.state_file, args.mode)
    change_dir = change_dir_from_state(path)
    log_path = os.path.join(change_dir, "agent_dispatch.log")
    log_entry = {
        "step": args.step or "",
        "agent_type": args.agent or "",
        "task": args.task or "",
        "ts": now_iso(),
    }
    with open(log_path, "a") as f:
        f.write(json.dumps(log_entry, ensure_ascii=False) + "\n")
    print(json.dumps({"status": "ok", "dispatch_log": log_path}, ensure_ascii=False))


def cmd_find(args):
    """查找活跃状态文件"""
    path, stype = find_state_file(args.mode)
    if path:
        print(json.dumps({"found": True, "path": path, "type": stype}, ensure_ascii=False))
    else:
        print(json.dumps({"found": False}, ensure_ascii=False))


def main():
    parser = argparse.ArgumentParser(
        prog="beggar-state",
        description="beggar workflow 状态文件管理工具",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    # init
    p_init = sub.add_parser("init", help="初始化 goal-state.json")
    p_init.add_argument("--goal", help="目标描述")
    p_init.add_argument("--target-dir", help="目标目录（默认 openspec/changes/goal-pending）")
    p_init.add_argument("--max-iterations", type=int, help="最大迭代数")
    p_init.add_argument("--max-agent-calls", type=int, help="最大 Agent 调用数")
    p_init.add_argument("--no-progress-limit", type=int, help="连续无进展上限")
    p_init.add_argument("--human-reject-limit", type=int, help="人工驳回上限")
    p_init.add_argument("--director-final-review", action="store_true", help="启用 Director 终审")
    p_init.add_argument("--stop-after-turns", type=int, help="停止轮次")
    p_init.add_argument("--stop-after-minutes", type=int, help="停止时间（分钟）")
    p_init.add_argument("--step", help="初始 current_step 值（默认 0.1-clarification，--force 覆盖时可设为 0.5-pipeline）")
    p_init.add_argument("--force", action="store_true", help="覆盖已有文件")
    p_init.set_defaults(func=cmd_init)

    # set
    p_set = sub.add_parser("set", help="设置单个字段")
    p_set.add_argument("field", help="字段名")
    p_set.add_argument("value", help="字段值（支持 true/false/null/int/string）")
    p_set.add_argument("--state-file", help="显式指定状态文件路径")
    p_set.add_argument("--mode", choices=["auto", "goal", "start"], default="auto", help="查找模式")
    p_set.set_defaults(func=cmd_set)

    # get
    p_get = sub.add_parser("get", help="读取单个字段")
    p_get.add_argument("field", help="字段名")
    p_get.add_argument("--state-file", help="显式指定状态文件路径")
    p_get.add_argument("--mode", choices=["auto", "goal", "start"], default="auto", help="查找模式")
    p_get.set_defaults(func=cmd_get)

    # post-call
    p_post = sub.add_parser("post-call", help="Agent 调用后置位")
    p_post.add_argument("--step", help="步骤号（如 0.4, 6.5.1）")
    p_post.add_argument("--agent", help="Agent 类型（如 director, goal-evaluator）")
    p_post.add_argument("--task", help="任务简述")
    p_post.add_argument("--lock", help="状态锁字段名（设为 true）")
    p_post.add_argument("--extra", help="额外字段 JSON（如 '{\"evaluator_verdict\":\"achieved\"}'）")
    p_post.add_argument("--step-id", help="completed_steps 步骤标识")
    p_post.add_argument("--state-file", help="显式指定状态文件路径")
    p_post.add_argument("--mode", choices=["auto", "goal", "start"], default="auto", help="查找模式")
    p_post.set_defaults(func=cmd_post_call)

    # check
    p_check = sub.add_parser("check", help="安全边界检查")
    p_check.add_argument("--state-file", help="显式指定状态文件路径")
    p_check.add_argument("--mode", choices=["auto", "goal", "start"], default="auto", help="查找模式")
    p_check.set_defaults(func=cmd_check)

    # reset
    p_reset = sub.add_parser("reset", help="重置单轮状态锁")
    p_reset.add_argument("--state-file", help="显式指定状态文件路径")
    p_reset.add_argument("--mode", choices=["auto", "goal", "start"], default="auto", help="查找模式")
    p_reset.set_defaults(func=cmd_reset)

    # step
    p_step = sub.add_parser("step", help="更新 current_step")
    p_step.add_argument("step", help="步骤值（如 0.1-clarification, iterating）")
    p_step.add_argument("--state-file", help="显式指定状态文件路径")
    p_step.add_argument("--mode", choices=["auto", "goal", "start"], default="auto", help="查找模式")
    p_step.set_defaults(func=cmd_step)

    # achieve
    p_achieve = sub.add_parser("achieve", help="标记目标达成")
    p_achieve.add_argument("--state-file", help="显式指定状态文件路径")
    p_achieve.add_argument("--mode", choices=["auto", "goal", "start"], default="auto", help="查找模式")
    p_achieve.set_defaults(func=cmd_achieve)

    # dispatch
    p_dispatch = sub.add_parser("dispatch", help="追加 agent_dispatch.log")
    p_dispatch.add_argument("--step", help="步骤号")
    p_dispatch.add_argument("--agent", help="Agent 类型")
    p_dispatch.add_argument("--task", help="任务简述")
    p_dispatch.add_argument("--state-file", help="显式指定状态文件路径")
    p_dispatch.add_argument("--mode", choices=["auto", "goal", "start"], default="auto", help="查找模式")
    p_dispatch.set_defaults(func=cmd_dispatch)

    # find
    p_find = sub.add_parser("find", help="查找活跃状态文件")
    p_find.add_argument("--mode", choices=["auto", "goal", "start"], default="auto", help="查找模式")
    p_find.set_defaults(func=cmd_find)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
