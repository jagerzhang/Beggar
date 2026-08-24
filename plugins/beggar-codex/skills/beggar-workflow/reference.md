# Codex 运行参考

本文件是参数参考，不替代 `SKILL.md`、`phases.md` 或 `router.md`。

## 设计理由

Luna 面向成本敏感、高吞吐工作负载，Terra 用于常规跨文件开发的质量/成本平衡，Sol 用于高风险和终裁。三者都支持按运行时暴露的 `reasoning_effort` 选择强度；工程质量来自自动风险路由、角色隔离、真实测试证据、结构化 FINDING 和有限重试，而不是单次生成的模型强度。

官方资料：

- [GPT-5.6 Luna](https://developers.openai.com/api/docs/models/gpt-5.6-luna)
- [GPT-5.6 Terra](https://developers.openai.com/api/docs/models/gpt-5.6-terra)
- [GPT-5.6 Sol](https://developers.openai.com/api/docs/models/gpt-5.6-sol)
- [模型选择与 reasoning effort](https://developers.openai.com/api/docs/guides/latest-model)

## 参数原则

1. L1 简单明确任务使用 Luna；L2 常规跨文件/API/数据库/性能任务使用 Terra；L3 硬风险、不可逆变更、审查争议或重复失败使用 Sol。
2. 普通成功路径直接执行真实测试命令，不默认启动 Tester；L2 风险或失败、高风险 L3 才启动 Tester。
3. MR 模式 Reviewer 沿用当前档位的 `xhigh`；L3 使用 Sol `high/xhigh`。
4. Director 只在三轮无进展、重大争议或重大风险时使用 Sol `max`。
5. 升级必须记录失败证据和理由，问题解决后普通任务可回落到原档位。
6. 如果运行时不接受某个模型 slug，应记录失败并使用当前可用的等价模型，不自行编造模型名。
7. OpenSpec CLI 是可选依赖：可用时使用 OpenSpec schema；不可用时使用 `proposal.md`、`design.md`、`tasks.md`、`test-plan.md` 的 Markdown 降级路径，并在 `start-state.json` 记录 `openspec_cli_unavailable`。

## 调用量

普通 task 默认需要 `1 Architect + 1 Coder + 真实测试命令`；进入 MR 模式时再增加 `1 独立 MR Reviewer` 和严格 MR 闭环。测试失败或高风险时按需增加 Tester。失败时按门禁增加调用，超过状态文件上限必须暂停。
