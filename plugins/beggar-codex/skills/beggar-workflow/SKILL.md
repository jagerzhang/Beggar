---
name: beggar-workflow
description: Codex 原生 Beggar 研发工作流：按任务风险自动选择 Luna/Terra/Sol，结合真实测试和统一 MR 审查收口。
metadata:
  short-description: 低成本实现、风险分级和单 MR 质量闭环
  runtime: codex-native
---

# Beggar for Codex

本技能由 Leader 编排 Architect、Coder 和独立 Reviewer。Leader 先按任务信号自动选择 Luna/Terra/Sol 档位，再分派子智能体；测试优先执行真实命令，进入 GitHub PR 或其他交付审查阶段时完成最终质量收口。

## 硬规则

1. 代码实现、独立审查和需要模型判断的失败分析必须使用 Codex 子智能体；使用 `multi_agent_v1__spawn_agent` 创建并用 `multi_agent_v1__wait_agent` 等待。Leader 不得把自己的判断伪装成子智能体结论。
2. 每个 change 必须有方案产物和真实测试证据；进入 MR 模式时再增加一次独立全量审查。测试不能被模型口头结论替代。
3. 普通 task 不强制启动 Tester 和 Reviewer 子智能体：先直接执行最小真实测试命令；只有高风险、测试失败、测试复杂或需要解释测试覆盖时才启动 Tester。
4. 不再对每个 task 做完整 Reviewer；进入 MR 模式后，按 `references/mr-loop.md` 对同一个 MR 做独立 Review、修复、测试和复审。
5. 进入 MR 模式后，同一个 `change_id` 只允许一个 source branch 和一个未合并 MR。优先读取 `start-state.json` 中的 `mr.iid`，再按分支查询；禁止因流程重启或分支描述变化而静默新开 MR。
6. 每次子智能体返回、测试完成、MR 状态变化后更新 `start-state.json` 和 `agent_dispatch.log`；上下文压缩后先读状态，禁止重复已完成步骤。
7. 并行只允许用于写入文件集合不相交、没有共享接口/迁移/配置且互不依赖的 task；push、review、修复和 merge 必须串行。
8. 不使用旧版 `agentType`、`waitCompletion`、`forkContext`、`use_mcp_tool`、`beggar show` 或旧平台模型预设。
9. Coder 和 Reviewer 必须按变更文件语言读取当前 Codex skill 根目录下对应的 `rules/` 规范文件；不得读取旧版 `.agent` 规则作为 Codex 流程的规范来源。
10. 分派前必须执行 `beggar-state.py route` 或等价的确定性路由计算，记录 `tier`、`score`、`reasons`、模型和 `reasoning_effort`；不得仅按角色名称或主观感觉选模型。

各角色的 Codex-native Prompt Contract、参数和输出格式统一见 `codex-runtime.md`；Leader 调用时只需补充当前 task 上下文，不得恢复旧版 `agentType` 路由。

## 模型与 effort 策略

| 节点 | L1 fast（简单明确） | L2 standard（常规开发） | L3 high-assurance（高风险） |
|---|---|---|---|
| Architect | 清晰需求可跳过；Luna `medium` | Terra `medium` | Sol `high` |
| Coder | Luna `high` | Terra `high` | Sol `high` |
| 测试命令 | shell/项目工具，零 LLM | 命令优先；失败或风险时启用 Tester | 必须真实命令，必要时启用 Tester |
| 独立 MR Reviewer | Luna `xhigh` | Terra `xhigh` | Sol `xhigh` |
| 修复 Coder | Luna `high` | Terra `high` | Sol `high` |
| Director | 不启用 | 连续失败或重大争议才启用 | Sol `max`，仅终裁 |

自动路由规则：`security_related`、`concurrency`、`production_incident`、`irreversible` 直接 L3；连续失败达到 2 轮或存在审查争议直接 L3；普通跨模块、API、数据库、重构、性能任务通常 L2；单文件、已有模式、验收清晰的任务为 L1。Luna/Terra/Sol 分别承担成本优先、平衡和质量优先档位。升级必须记录证据和理由，问题解决后普通任务可回落。effort 不能替代真实测试和独立审查。

## Skill 门控

- `beggar-brainstorming`：仅当需求、范围或验收标准存在实质歧义时启用，最多一次；需求清晰时跳过。
- `codegraph`：涉及跨模块、调用链、影响面或预计修改 2 个以上文件时启用；简单单文件任务直接 `rg`/读取。
- `openspec-*`：仅在 `command -v openspec` 成功时使用；CLI 缺失时走本技能定义的 Markdown 产物降级路径，并在状态中记录，不得假装执行了 OpenSpec。
- `github-workflow`：只有用户明确要求 GitHub PR 操作时启用；它负责 GitHub PR 创建、检查、Review 和反馈闭环，核心 workflow 不绑定具体平台。
- `ponytail`：只作为实现阶段的简化建议，不替代测试、审查和风险门禁。
- 不依赖未安装的 `superpowers` brainstorming；当前 Codex 使用已有的 `beggar-brainstorming`，避免重复注入两套澄清流程。

## 统一流程

1. Phase 0：确认工作区和已有修改，检测 `openspec` CLI，初始化唯一 `change_id`、状态文件并执行一次自动路由；代码理解按需使用通用 `codegraph` skill。
2. Phase 1：需求与架构，按路由档位决定是否需要 Architect，产出 `proposal.md`、`design.md`、`tasks.md`、`test-plan.md`。
3. Phase 2：独立方案审查；不通过回到 Architect，最多 3 轮。
4. Phase 3：Coder 按 task 实现；每个 task 执行确定性测试命令，必要时才启动 Tester。
5. Phase 4：只有用户明确要求提交 GitHub PR 或其他平台变更时，才启用对应的平台适配器。
6. Phase 5：进入 PR 模式后，由平台适配器完成独立 Review、修复、测试和复审；本地交付直接以测试和独立 Reviewer 结果收口。
7. Phase 6：所有 task、关键测试和必要的 Review 通过后，按用户授权交付或归档。

## Definition of Done

- 代码范围符合 design.md，新增行为有测试或明确的真实验证证据；
- 测试报告包含完整命令、退出码和真实输出摘要；环境阻塞与代码失败分开记录；
- 进入 MR 模式时，独立 MR Reviewer 检查 Bug、安全、错误处理、边界、并发、资源、性能、API 契约、测试有效性和简化；
- 没有 blocker/major；minor 已记录；
- `start-state.json` 保存 task 完成度、MR IID/分支/状态、测试结果、审查轮次和模型升级原因；
- 如果启用 MR 模式，未合并 MR 不得被新 change 静默复用，已合并或已关闭 MR 不得被当前 change 静默替换。

## 轻量路径

纯文档、纯配置或无行为的一行修改可跳过 Architect 子智能体和独立 Tester，但仍需范围检查和确定性验证；只有启用 MR 模式时才需要 MR Review。

涉及删除、生产发布、不可逆迁移、外部消息或凭证时，另行请求用户确认。
