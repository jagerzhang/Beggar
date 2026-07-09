"""beggar_state.py 单元测试"""
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

import pytest

STATE_SCRIPT = str(Path(__file__).parent.parent / "beggar_state.py")


@pytest.fixture
def temp_project(tmp_path):
    """创建临时项目结构"""
    changes_dir = tmp_path / "openspec" / "changes" / "goal-pending"
    changes_dir.mkdir(parents=True)
    os.chdir(tmp_path)
    yield tmp_path
    os.chdir("/Users/jager/With/beggar")


def run_state_cmd(*args, cwd=None):
    """运行 beggar_state.py 命令"""
    cmd = [sys.executable, STATE_SCRIPT] + list(args)
    result = subprocess.run(cmd, capture_output=True, text=True, cwd=cwd)
    return result


class TestInit:
    def test_init_creates_state_file(self, temp_project):
        result = run_state_cmd("init", "--goal", "测试目标")
        assert result.returncode == 0
        data = json.loads(result.stdout)
        assert data["status"] == "created"

        state_path = temp_project / "openspec" / "changes" / "goal-pending" / "goal-state.json"
        assert state_path.exists()

        with open(state_path) as f:
            state = json.load(f)
        assert state["goal"] == "测试目标"
        assert state["status"] == "in_progress"
        assert state["current_iteration"] == 0
        assert state["agent_calls_used"] == 0
        assert state["completed_steps"] == []
        assert state["human_reject_limit"] == 3

    def test_init_custom_params(self, temp_project):
        result = run_state_cmd(
            "init", "--goal", "自定义",
            "--max-iterations", "5",
            "--max-agent-calls", "50",
            "--human-reject-limit", "2",
            "--director-final-review",
        )
        assert result.returncode == 0

        state_path = temp_project / "openspec" / "changes" / "goal-pending" / "goal-state.json"
        with open(state_path) as f:
            state = json.load(f)
        assert state["max_iterations"] == 5
        assert state["max_agent_calls"] == 50
        assert state["human_reject_limit"] == 2
        assert state["director_final_review"] is True

    def test_init_skip_if_exists(self, temp_project):
        run_state_cmd("init", "--goal", "第一次")
        result = run_state_cmd("init", "--goal", "第二次")
        assert result.returncode == 0
        data = json.loads(result.stdout)
        assert data["status"] == "exists"

    def test_init_force_overwrite(self, temp_project):
        run_state_cmd("init", "--goal", "第一次")
        result = run_state_cmd("init", "--goal", "第二次", "--force")
        assert result.returncode == 0
        data = json.loads(result.stdout)
        assert data["status"] == "created"


class TestSetGet:
    def test_set_string_field(self, temp_project):
        run_state_cmd("init", "--goal", "测试")
        result = run_state_cmd("set", "current_step", "0.5-pipeline")
        assert result.returncode == 0
        data = json.loads(result.stdout)
        assert data["field"] == "current_step"
        assert data["value"] == "0.5-pipeline"

    def test_set_bool_field(self, temp_project):
        run_state_cmd("init", "--goal", "测试")
        result = run_state_cmd("set", "evaluator_done", "true")
        assert result.returncode == 0
        data = json.loads(result.stdout)
        assert data["value"] is True

    def test_set_int_field(self, temp_project):
        run_state_cmd("init", "--goal", "测试")
        result = run_state_cmd("set", "current_iteration", "3")
        assert result.returncode == 0
        data = json.loads(result.stdout)
        assert data["value"] == 3

    def test_set_null_field(self, temp_project):
        run_state_cmd("init", "--goal", "测试")
        # 先设为有值
        run_state_cmd("set", "evaluator_verdict", "achieved")
        # 再设为 null
        result = run_state_cmd("set", "evaluator_verdict", "null")
        assert result.returncode == 0
        data = json.loads(result.stdout)
        assert data["value"] is None

    def test_get_field(self, temp_project):
        run_state_cmd("init", "--goal", "测试")
        result = run_state_cmd("get", "status")
        assert result.returncode == 0
        data = json.loads(result.stdout)
        assert data["field"] == "status"
        assert data["value"] == "in_progress"


class TestPostCall:
    def test_post_call_increments_counter(self, temp_project):
        run_state_cmd("init", "--goal", "测试")
        result = run_state_cmd("post-call", "--step", "0.4", "--agent", "director", "--task", "目标审定")
        assert result.returncode == 0
        data = json.loads(result.stdout)
        assert data["agent_calls_used"] == 1

    def test_post_call_sets_lock(self, temp_project):
        run_state_cmd("init", "--goal", "测试")
        result = run_state_cmd("post-call", "--step", "0.4", "--agent", "director",
                                "--lock", "director_target_review_done", "--task", "目标审定")
        assert result.returncode == 0
        data = json.loads(result.stdout)
        assert "director_target_review_done" in data["locks_set"]

        # 验证状态文件
        result2 = run_state_cmd("get", "director_target_review_done")
        data2 = json.loads(result2.stdout)
        assert data2["value"] is True

    def test_post_call_with_extra_fields(self, temp_project):
        run_state_cmd("init", "--goal", "测试")
        result = run_state_cmd("post-call", "--step", "6.5.1", "--agent", "goal-evaluator",
                                "--lock", "evaluator_done",
                                "--extra", '{"evaluator_verdict":"achieved","evaluator_confidence":"high","evaluator_reason":"所有验收标准通过"}',
                                "--task", "独立判定")
        assert result.returncode == 0
        data = json.loads(result.stdout)
        assert "evaluator_verdict" in data["extras_set"]

    def test_post_call_adds_step_id(self, temp_project):
        run_state_cmd("init", "--goal", "测试")
        result = run_state_cmd("post-call", "--step", "2", "--agent", "architect",
                                "--step-id", "0-2-architect", "--task", "方案设计")
        assert result.returncode == 0

        result2 = run_state_cmd("get", "completed_steps")
        data2 = json.loads(result2.stdout)
        assert "0-2-architect" in data2["value"]

    def test_post_call_appends_dispatch_log(self, temp_project):
        run_state_cmd("init", "--goal", "测试")
        run_state_cmd("post-call", "--step", "0.4", "--agent", "director", "--task", "目标审定")

        log_path = temp_project / "openspec" / "changes" / "goal-pending" / "agent_dispatch.log"
        assert log_path.exists()
        with open(log_path) as f:
            line = f.readline()
        entry = json.loads(line)
        assert entry["agent_type"] == "director"
        assert entry["step"] == "0.4"


class TestCheck:
    def test_check_passes_on_fresh_state(self, temp_project):
        run_state_cmd("init", "--goal", "测试")
        result = run_state_cmd("check")
        assert result.returncode == 0
        data = json.loads(result.stdout)
        assert data["should_pause"] is False

    def test_check_fails_on_max_iterations(self, temp_project):
        run_state_cmd("init", "--goal", "测试", "--max-iterations", "2")
        run_state_cmd("set", "current_iteration", "2")
        result = run_state_cmd("check")
        assert result.returncode == 2  # should_pause exits with 2
        data = json.loads(result.stdout)
        assert data["should_pause"] is True
        assert any(r["check"] == "max_iterations" and not r["passed"] for r in data["results"])

    def test_check_fails_on_max_agent_calls(self, temp_project):
        run_state_cmd("init", "--goal", "测试", "--max-agent-calls", "5")
        # 做 6 次调用
        for i in range(6):
            run_state_cmd("post-call", "--step", "test", "--agent", "test")
        result = run_state_cmd("check")
        assert result.returncode == 2
        data = json.loads(result.stdout)
        assert any(r["check"] == "max_agent_calls" and not r["passed"] for r in data["results"])

    def test_check_human_reject_triggers_director_not_pause(self, temp_project):
        run_state_cmd("init", "--goal", "测试", "--human-reject-limit", "3")
        run_state_cmd("set", "human_reject_count", "3")
        result = run_state_cmd("check")
        # human_reject 触发 Director 介入但不暂停，所以 returncode 应为 0
        assert result.returncode == 0
        data = json.loads(result.stdout)
        reject_result = [r for r in data["results"] if r["check"] == "human_reject_count"][0]
        assert reject_result["passed"] is False
        assert "Director" in reject_result["action"]


class TestReset:
    def test_reset_increments_iteration(self, temp_project):
        run_state_cmd("init", "--goal", "测试")
        result = run_state_cmd("reset")
        assert result.returncode == 0
        data = json.loads(result.stdout)
        assert data["current_iteration"] == 1

    def test_reset_clears_state_locks(self, temp_project):
        run_state_cmd("init", "--goal", "测试")
        # 设置一些状态锁
        run_state_cmd("set", "evaluator_done", "true")
        run_state_cmd("set", "evaluator_verdict", "achieved")
        run_state_cmd("set", "director_dispute_review_done", "true")

        result = run_state_cmd("reset")
        assert result.returncode == 0

        # 验证重置
        assert json.loads(run_state_cmd("get", "evaluator_done").stdout)["value"] is False
        assert json.loads(run_state_cmd("get", "evaluator_verdict").stdout)["value"] is None
        assert json.loads(run_state_cmd("get", "director_dispute_review_done").stdout)["value"] is False

    def test_reset_clears_completed_steps(self, temp_project):
        run_state_cmd("init", "--goal", "测试")
        run_state_cmd("post-call", "--step", "2", "--agent", "architect",
                       "--step-id", "0-2-architect", "--task", "方案设计")

        result = run_state_cmd("reset")
        assert result.returncode == 0

        steps = json.loads(run_state_cmd("get", "completed_steps").stdout)["value"]
        assert steps == []

    def test_reset_keeps_director_target_review(self, temp_project):
        run_state_cmd("init", "--goal", "测试")
        run_state_cmd("set", "director_target_review_done", "true")

        run_state_cmd("reset")

        result = json.loads(run_state_cmd("get", "director_target_review_done").stdout)
        assert result["value"] is True

    def test_reset_keeps_human_reject_count(self, temp_project):
        run_state_cmd("init", "--goal", "测试")
        run_state_cmd("set", "human_reject_count", "2")

        run_state_cmd("reset")

        result = json.loads(run_state_cmd("get", "human_reject_count").stdout)
        assert result["value"] == 2


class TestStep:
    def test_step_update(self, temp_project):
        run_state_cmd("init", "--goal", "测试")
        result = run_state_cmd("step", "0.1.1-config")
        assert result.returncode == 0
        data = json.loads(result.stdout)
        assert data["current_step"] == "0.1.1-config"


class TestAchieve:
    def test_achieve(self, temp_project):
        run_state_cmd("init", "--goal", "测试")
        result = run_state_cmd("achieve")
        assert result.returncode == 0
        data = json.loads(result.stdout)
        assert data["status"] == "achieved"

        state = json.loads(run_state_cmd("get", "status").stdout)
        assert state["value"] == "achieved"
        step = json.loads(run_state_cmd("get", "current_step").stdout)
        assert step["value"] == "achieved"


class TestFind:
    def test_find_active_goal(self, temp_project):
        run_state_cmd("init", "--goal", "测试")
        result = run_state_cmd("find")
        assert result.returncode == 0
        data = json.loads(result.stdout)
        assert data["found"] is True
        assert data["type"] == "goal"

    def test_find_none(self, tmp_path):
        os.chdir(tmp_path)
        result = run_state_cmd("find")
        assert result.returncode == 0
        data = json.loads(result.stdout)
        assert data["found"] is False
        os.chdir("/Users/jager/With/beggar")


class TestDispatch:
    def test_dispatch_append(self, temp_project):
        run_state_cmd("init", "--goal", "测试")
        result = run_state_cmd("dispatch", "--step", "4.1", "--agent", "coder-standard", "--task", "Task 1")
        assert result.returncode == 0

        log_path = temp_project / "openspec" / "changes" / "goal-pending" / "agent_dispatch.log"
        with open(log_path) as f:
            lines = f.readlines()
        assert len(lines) == 1
        entry = json.loads(lines[0])
        assert entry["agent_type"] == "coder-standard"
