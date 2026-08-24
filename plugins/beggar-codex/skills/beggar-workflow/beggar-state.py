#!/usr/bin/env python3
"""beggar-state: 状态文件管理工具

封装 beggar workflow 中所有固定状态操作，减少 Leader token 消耗。

子命令:
  init        初始化 start-state.json
  set         设置单个字段
  get         读取单个字段
  mr-bind     绑定或更新当前 change 的 MR
  mr-clear    清除当前 change 的 MR 绑定
  post-call   Agent 调用后置位（递增计数 + 设置锁 + 追加日志）
  check       安全边界检查
  reset       重置单轮状态锁
  step        更新 current_step
  achieve     标记目标达成
  dispatch    追加 agent_dispatch.log
  route       按任务信号计算模型档位
  find        查找活跃状态文件
"""
import json
import os
import sys
import argparse
import shutil
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
        active = []
        fallback = None
        for d in sorted(os.listdir(openspec_dir)):
            goal_dir = os.path.join(openspec_dir, d)
            if not os.path.isdir(goal_dir):
                continue
            state_path = os.path.join(goal_dir, "start-state.json")
            if os.path.isfile(state_path):
                try:
                    with open(state_path) as f:
                        data = json.load(f)
                    if data.get("status") == "in_progress":
                        active.append((state_path, "goal"))
                    if fallback is None:
                        fallback = (state_path, "goal")
                except (json.JSONDecodeError, IOError):
                    continue
        if len(active) > 1:
            return None, "ambiguous"
        if active:
            return active[0]
        if fallback:
            return fallback

    if mode in ("auto", "start"):
        active = []
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
                        active.append((state_path, "start"))
                except (json.JSONDecodeError, IOError):
                    continue
        if len(active) > 1:
            return None, "ambiguous"
        if active:
            return active[0]

    return None, None


def get_state_path(explicit_path=None, mode="auto"):
    """获取状态文件路径，优先使用显式指定路径"""
    if explicit_path:
        return explicit_path, "start"
    path, stype = find_state_file(mode)
    if stype == "ambiguous":
        print(json.dumps({
            "error": "发现多个活跃状态文件，不能自动猜测",
            "hint": "请使用 --state-file 明确指定当前 change 的 start-state.json",
        }, ensure_ascii=False), file=sys.stderr)
        sys.exit(2)
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


def cmd_route(args):
    """按可观察任务信号选择 Luna/Terra/Sol 档位，不调用模型。"""
    tags = {tag.strip() for tag in (args.tags or "").split(",") if tag.strip()}
    reasons = []
    score = 0

    points = {
        "ui_component": 1,
        "api_endpoint": 1,
        "cross_module": 1,
        "refactor": 1,
        "bugfix_complex": 1,
        "performance": 2,
        "database": 2,
        "security_related": 3,
        "concurrency": 3,
        "production_incident": 3,
        "irreversible": 2,
    }
    for tag in sorted(tags):
        if tag in points:
            score += points[tag]
            reasons.append(tag)

    if args.files >= 6:
        score += 2
        reasons.append("6+ files")
    elif args.files >= 2:
        score += 1
        reasons.append("2-5 files")
    for enabled, label in (
        (args.ambiguous, "ambiguous requirement"),
        (args.novel, "no existing pattern"),
        (args.test_unclear, "unclear test command"),
        (args.irreversible, "irreversible change"),
        (args.review_dispute, "review dispute"),
    ):
        if enabled:
            score += 1 if label not in ("irreversible change", "review dispute") else 2
            reasons.append(label)
    if args.failure_rounds:
        score += min(args.failure_rounds, 2)
        reasons.append(f"failure rounds={args.failure_rounds}")

    hard_risk = bool(tags & {"security_related", "concurrency", "production_incident", "irreversible"}) or args.irreversible
    if hard_risk or args.failure_rounds >= 2 or args.review_dispute:
        tier = "L3"
    elif score >= 2:
        tier = "L2"
    else:
        tier = "L1"

    routes = {
        "L1": {
            "name": "fast",
            "architect": {"action": "skip_if_clear", "model": "gpt-5.6-luna", "reasoning_effort": "medium"},
            "coder": {"model": "gpt-5.6-luna", "reasoning_effort": "high"},
            "reviewer": {"model": "gpt-5.6-luna", "reasoning_effort": "xhigh"},
            "tester": "command_only",
        },
        "L2": {
            "name": "standard",
            "architect": {"model": "gpt-5.6-terra", "reasoning_effort": "medium"},
            "coder": {"model": "gpt-5.6-terra", "reasoning_effort": "high"},
            "reviewer": {"model": "gpt-5.6-terra", "reasoning_effort": "xhigh"},
            "tester": "on_failure_or_risk",
        },
        "L3": {
            "name": "high_assurance",
            "architect": {"model": "gpt-5.6-sol", "reasoning_effort": "high"},
            "coder": {"model": "gpt-5.6-sol", "reasoning_effort": "high"},
            "reviewer": {"model": "gpt-5.6-sol", "reasoning_effort": "xhigh"},
            "tester": "required",
            "director": {"model": "gpt-5.6-sol", "reasoning_effort": "max", "when": "after repeated failure or major dispute"},
        },
    }
    result = {
        "tier": tier,
        "route": routes[tier],
        "score": score,
        "hard_risk": hard_risk,
        "reasons": reasons or ["simple, clear task"],
    }
    if args.state_file:
        path, _ = get_state_path(args.state_file, args.mode)
        data = load_state(path)
        route = result["route"]
        data["routing"] = {
            "tier": tier,
            "route_name": route["name"],
            "score": score,
            "hard_risk": hard_risk,
            "reasons": result["reasons"],
            "route": route,
            "updated_at": now_iso(),
        }
        save_state(path, data)
        result["state_file"] = path
    print(json.dumps(result, ensure_ascii=False, indent=2))


def change_dir_from_state(state_path):
    """从状态文件路径推导 change 目录"""
    return os.path.dirname(state_path)


# ─── subcommands ─────────────────────────────────────────────

def cmd_init(args):
    """初始化 start-state.json"""
    target_dir = args.target_dir
    if not target_dir:
        # 默认 goal-pending 目录
        target_dir = os.path.join(os.getcwd(), "openspec", "changes", "goal-pending")
    os.makedirs(target_dir, exist_ok=True)
    state_path = os.path.join(target_dir, "start-state.json")

    if os.path.exists(state_path) and not args.force:
        print(json.dumps({"status": "exists", "path": state_path, "hint": "使用 --force 覆盖"}))
        return

    now = now_iso()
    change_id = os.path.basename(os.path.abspath(target_dir))
    data = {
        "schema_version": 2,
        "change_id": change_id,
        "goal": args.goal or "",
        "status": "in_progress",
        "current_step": args.step or "0.1-clarification",
        "current_iteration": 0,
        "max_iterations": args.max_iterations or 6,
        "max_agent_calls": args.max_agent_calls or 48,
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
        "pipeline": {
            "mode": "local-first",
            "mr_enabled": False,
            "artifact_mode": "openspec" if shutil.which("openspec") else "markdown-fallback",
            "openspec_cli_unavailable": shutil.which("openspec") is None,
            "test_policy": "command_first",
            "per_task_reviewer": False,
            "per_task_tester_agent": "on_failure_or_risk",
            "mr_review_round_limit": 2,
        },
        "routing": {
            "tier": None,
            "route_name": None,
            "score": 0,
            "hard_risk": False,
            "reasons": [],
            "escalation_count": 0,
        },
        "tasks": {
            "total": 0,
            "completed": 0,
            "pending": [],
        },
        "mr": {
            "status": "none",
            "project_id": None,
            "global_id": None,
            "iid": None,
            "source_branch": None,
            "target_branch": "master",
            "url": None,
            "head_sha": None,
        },
        "review_round": 0,
        "review_findings": [],
        "verification_results": [],
        "created_at": now,
        "updated_at": now,
    }
    save_state(state_path, data)
    print(json.dumps({"status": "created", "path": state_path}, ensure_ascii=False))


def cmd_mr_bind(args):
    """绑定或更新当前 change 的 MR 元数据，支持流程恢复和幂等复用。"""
    path, _ = get_state_path(args.state_file, args.mode)
    data = load_state(path)
    mr = data.setdefault("mr", {})
    fields = {
        "status": args.status,
        "project_id": args.project_id,
        "global_id": args.global_id,
        "iid": args.iid,
        "source_branch": args.branch,
        "target_branch": args.target_branch,
        "url": args.url,
        "head_sha": args.head_sha,
    }
    for key, value in fields.items():
        if value is not None:
            mr[key] = value
    mr["updated_at"] = now_iso()
    data["mr"] = mr
    data.setdefault("pipeline", {})["mr_enabled"] = mr.get("status") == "opened"
    if args.step:
        data["current_step"] = args.step
    save_state(path, data)
    print(json.dumps({"status": "ok", "mr": mr, "path": path}, ensure_ascii=False))


def cmd_mr_clear(args):
    """清除 MR 绑定，但保留历史信息，避免误把旧 MR 当成当前 MR。"""
    path, _ = get_state_path(args.state_file, args.mode)
    data = load_state(path)
    old_mr = data.get("mr", {})
    data["mr"] = {
        "status": "none",
        "project_id": None,
        "global_id": None,
        "iid": None,
        "source_branch": None,
        "target_branch": "master",
        "url": None,
        "head_sha": None,
        "previous": old_mr,
    }
    data.setdefault("pipeline", {})["mr_enabled"] = False
    save_state(path, data)
    print(json.dumps({"status": "cleared", "previous": old_mr, "path": path}, ensure_ascii=False))


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

    # 7. opened MR binding must be complete; otherwise a resumed workflow may
    # accidentally fall back to branch-name discovery and create a duplicate.
    mr = data.get("mr", {})
    if mr.get("status") == "opened":
        missing_mr = [field for field in ("project_id", "iid", "source_branch", "target_branch") if not mr.get(field)]
        if missing_mr or mr.get("target_branch") != "master":
            detail = f"missing={','.join(missing_mr)} target={mr.get('target_branch')}"
            results.append({"check": "mr_binding", "passed": False, "detail": detail, "action": "暂停，修复 start-state.json 的 MR 绑定后再继续"})
            should_pause = True
        else:
            results.append({"check": "mr_binding", "passed": True, "detail": f"!{mr.get('iid')} {mr.get('source_branch')} -> master"})
    else:
        results.append({"check": "mr_binding", "passed": True, "detail": f"status={mr.get('status', 'none')}"})

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
    data = load_state(path)
    if args.tier not in {"L1", "L2", "L3"} or not args.model or not args.reasoning_effort:
        print(json.dumps({
            "error": "dispatch 必须提供有效 tier、model 和 reasoning_effort",
            "hint": "先执行 beggar-state.py route，并使用路由结果分派",
        }, ensure_ascii=False), file=sys.stderr)
        sys.exit(2)
    expected_tier = data.get("routing", {}).get("tier")
    if expected_tier and args.tier != expected_tier:
        print(json.dumps({
            "error": "dispatch tier 与当前 routing 不一致",
            "expected": expected_tier,
            "received": args.tier,
            "hint": "先按失败轮次或新风险重新执行 route，再 dispatch",
        }, ensure_ascii=False), file=sys.stderr)
        sys.exit(2)
    change_dir = change_dir_from_state(path)
    log_path = os.path.join(change_dir, "agent_dispatch.log")
    log_entry = {
        "step": args.step or "",
        "agent_type": args.agent or "",
        "task": args.task or "",
        "tier": args.tier or "",
        "model": args.model or "",
        "reasoning_effort": args.reasoning_effort or "",
        "route_score": args.route_score,
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
    p_init = sub.add_parser("init", help="初始化 start-state.json")
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

    # mr-bind
    p_mr_bind = sub.add_parser("mr-bind", help="绑定或更新当前 change 的 MR")
    p_mr_bind.add_argument("--status", choices=["none", "opened", "closed", "merged", "blocked"], default="opened")
    p_mr_bind.add_argument("--project-id", type=int)
    p_mr_bind.add_argument("--global-id", type=int)
    p_mr_bind.add_argument("--iid", type=int)
    p_mr_bind.add_argument("--branch")
    p_mr_bind.add_argument("--target-branch", default="master")
    p_mr_bind.add_argument("--url")
    p_mr_bind.add_argument("--head-sha")
    p_mr_bind.add_argument("--step")
    p_mr_bind.add_argument("--state-file")
    p_mr_bind.add_argument("--mode", choices=["auto", "goal", "start"], default="auto")
    p_mr_bind.set_defaults(func=cmd_mr_bind)

    # mr-clear
    p_mr_clear = sub.add_parser("mr-clear", help="清除当前 change 的 MR 绑定")
    p_mr_clear.add_argument("--state-file")
    p_mr_clear.add_argument("--mode", choices=["auto", "goal", "start"], default="auto")
    p_mr_clear.set_defaults(func=cmd_mr_clear)

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
    p_dispatch.add_argument("--tier", help="路由档位（L1/L2/L3）")
    p_dispatch.add_argument("--model", help="实际使用的模型 slug")
    p_dispatch.add_argument("--reasoning-effort", help="实际使用的 reasoning effort")
    p_dispatch.add_argument("--route-score", type=int, help="路由评分")
    p_dispatch.add_argument("--state-file", help="显式指定状态文件路径")
    p_dispatch.add_argument("--mode", choices=["auto", "goal", "start"], default="auto", help="查找模式")
    p_dispatch.set_defaults(func=cmd_dispatch)

    # route
    p_route = sub.add_parser("route", help="按任务信号计算模型档位")
    p_route.add_argument("--tags", default="", help="逗号分隔的任务标签")
    p_route.add_argument("--files", type=int, default=1, help="预计修改文件数")
    p_route.add_argument("--ambiguous", action="store_true", help="需求存在歧义")
    p_route.add_argument("--novel", action="store_true", help="项目中没有可复用模式")
    p_route.add_argument("--test-unclear", action="store_true", help="测试命令或验收方式不清晰")
    p_route.add_argument("--irreversible", action="store_true", help="不可逆或高代价变更")
    p_route.add_argument("--review-dispute", action="store_true", help="存在审查争议")
    p_route.add_argument("--failure-rounds", type=int, default=0, help="当前任务已失败轮次")
    p_route.add_argument("--state-file", help="写入路由结果的 start-state.json")
    p_route.add_argument("--mode", choices=["auto", "goal", "start"], default="auto", help="查找模式")
    p_route.set_defaults(func=cmd_route)

    # find
    p_find = sub.add_parser("find", help="查找活跃状态文件")
    p_find.add_argument("--mode", choices=["auto", "goal", "start"], default="auto", help="查找模式")
    p_find.set_defaults(func=cmd_find)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
