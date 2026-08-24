# Beggar for Codex：统一交付阶段执行手册

所有 `spawn_agent` 的职责、Prompt 组装顺序和输出 Contract 以同目录 `codex-runtime.md` 为准；本文件只补充当前阶段的输入、产物和门禁。Codex 不使用旧版 `agentType`/`waitCompletion`。

## Phase 0：初始化

1. 确认项目根目录、当前分支和用户已有未提交修改；不得覆盖已有修改。
2. 检测 `command -v openspec`。可用时创建唯一 `openspec/changes/<change-id>/` 并按 OpenSpec schema 初始化；不可用时仍创建同一目录和 `start-state.json`，但使用 Markdown 产物降级路径并记录 `openspec_cli_unavailable`。
3. 需要代码关系分析时使用通用 `codegraph` skill；不可用则记录并回退到 `rg`/文件读取。
4. 根据任务标签、预计文件数、需求清晰度和失败轮次执行 `beggar-state.py route`，把路由结果写入状态；后续子智能体沿用该档位，除非触发升级门禁。

## Phase 1：需求与方案

需求清晰时直接分派 Architect；模糊时最多使用一次 `beggar-brainstorming` 完成澄清。若 `openspec` CLI 可用，按 OpenSpec 产出；否则由 Architect 直接写入同目录的 Markdown 产物。Architect 必须产出：

- `proposal.md`：目标、范围、非目标和验收标准；
- `design.md`：方案、错误处理、兼容性、性能、回滚和明确文件范围；
- `tasks.md`：可独立验收的 task、依赖和写入文件集合；
- `test-plan.md`：最小测试、回归测试和环境前置条件。

清晰且简单的方案可跳过 Architect；L1 用 Luna `medium`，L2 常规方案用 Terra `medium`，L3 的安全、并发、不可逆、生产事故或明显不确定性用 Sol `high`。

## Phase 2：方案门禁

按当前路由档位独立审查：L1 用 Luna `xhigh`，L2 用 Terra `xhigh`，L3 用 Sol `high/xhigh`。检查需求、文件范围、可测试性、兼容性、安全、复杂度、回滚和是否能简化。

- 通过：进入 Phase 3；
- 驳回：Architect 修正后重审，最多 3 轮；
- 第 2 轮仍为架构分歧：升级 L3，使用 Sol `xhigh`；
- 第 3 轮仍不通过：暂停，请用户裁决。

## Phase 3：实现与验证

### 3.1 Coder

Coder 使用当前路由档位：L1 Luna `high`、L2 Terra `high`、L3 Sol `high`。Prompt 必须包含唯一目标、设计片段、允许文件、验收标准和最小测试命令。Coder 首次编辑前必须读取涉及语言的 Codex `rules/` 规范，并在报告中列出已读取文件；不得读取 `.agent` 规则。Coder 完成后执行 `git diff --name-only`，发现越界先停止门禁。

### 3.2 测试策略

先由 Leader 或脚本直接执行 `test-plan.md` 中的最小真实命令，记录命令、退出码和输出摘要。普通成功路径不启动 Tester 子智能体。

以下情况才启动 Tester：

- 测试失败，需要分析根因；
- 并发、迁移、复杂集成或环境依赖导致结果难以判断；
- 高风险 task 需要独立确认测试覆盖；
- 用户明确要求独立测试报告。

Tester 只验证不改业务代码。测试失败最多修复 2 次；环境阻塞必须单独标记，不能伪装为代码通过。

### 3.3 Task 收口

task 通过范围检查和真实测试后即可标记完成，不再启动 task 级 Reviewer。进入 MR 模式后，按 `references/mr-loop.md` 对所有 task 的 diff 做独立全量检查；Reviewer 首次审查前必须读取全量 diff 涉及的 Codex `rules/` 规范，并在报告中列出已读取文件。

## Phase 4：创建或更新 Pull Request（可选）

只有用户明确要求进入 GitHub PR 或其他平台交付模式时，才启用平台适配器。核心流程只
负责提供已验证的提交和审查输入，不直接假设某个平台的 API、认证方式或命令。

GitHub 适配器应：

1. 读取当前 change 的状态、分支和已完成 task；
2. 复用同一 source branch 上已有的 opened PR，不因流程重启静默创建重复 PR；
3. 在创建或更新 PR 前确认目标仓库、目标分支和实际 diff；
4. 将 PR 标识、提交 SHA 和平台状态写回状态文件；
5. 平台认证失败时停止平台操作，但不阻断本地测试和交付报告。

## Phase 5：Pull Request Review（可选）

用户明确要求进入 PR 模式后，平台适配器按以下闭环执行：

```text
获取 PR diff → 按路由档位启动独立 Reviewer → 生成结构化 findings
    ├─ 无 blocker/major：通过
    └─ 有问题：Coder 修复 → 真实测试 → Reviewer 复审
```

普通 PR Review 按当前路由档位使用对应 reasoning effort；高风险、第二轮失败或审查分歧
升级到 L3。最多进行有限轮次，仍不收敛时由 Director 做根因分析或暂停请求用户裁决。

## Phase 6：合并与归档

只有以下条件同时满足才允许合并或标记平台交付完成：

- 所有 task 完成；
- PR Review 无 blocker/major；
- 关键测试通过；
- 平台状态、source branch 和 target branch 与状态文件一致；
- 用户明确授权自动合并，或用户在平台手动合并。

合并或交付后，由 Recorder 使用低成本模型记录变更摘要、决策、验证命令和已知限制。未
合并 PR 不得归档为已完成。

## 状态推进

每次子智能体返回、测试完成、MR 创建/复用、review 轮次变化后，更新 `start-state.json` 和 `agent_dispatch.log`。调用 `beggar-state.py check` 做上限检查；超过 `max_agent_calls`、`max_iterations` 或连续 3 次无进展就暂停。
