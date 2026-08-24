# Codex 任务路由与失败升级

## 标签

从以下标签选择 1–3 个：`config_edit`、`crud_field`、`copy_pattern`、`api_endpoint`、`ui_component`、`cross_module`、`security_related`、`concurrency`、`performance`、`database`、`test_only`、`docs_only`、`refactor`、`bugfix_simple`、`bugfix_complex`、`production_incident`。

## 自动路由

分派前执行：

```bash
python3 <beggar-skills-root>/beggar-workflow/beggar-state.py route \
  --tags "<tags>" --files <n> [风险/失败选项]
```

| 档位 | 典型信号 | Architect | Coder | 测试 | MR Reviewer |
|---|---|---:|---:|---:|---:|
| L1 fast | 单文件、已有模式、验收清晰 | 清晰时跳过；否则 Luna medium | Luna high | 真实命令 | Luna xhigh |
| L2 standard | API、跨模块、数据库、性能、重构或轻微不确定性 | Terra medium | Terra high | 命令优先；失败/风险时 Tester | Terra xhigh |
| L3 high-assurance | 安全、并发、生产事故、不可逆变更、审查争议、失败达到 2 轮 | Sol high | Sol high | 真实命令 + Tester | Sol xhigh |

评分与 `beggar-state.py route` 保持一致：L1 低于 2 分，L2 至少 2 分，硬风险和失败/争议门禁直接 L3。`test_only`、`docs_only`、`config_edit` 通常 L1，但若涉及发布、凭证、迁移或不可逆操作，按硬风险升级。

路由结果要写入 `start-state.json.routing`；每次升级都记录触发原因，不得静默切换模型。Terra 是默认的常规开发平衡档，不把所有跨模块任务直接推到 Sol。

Tester 不是普通成功路径的默认子智能体；只有测试失败、复杂验证、高风险或用户明确要求时才启用。

## 失败分类

- **A 设计缺陷**：回到 Architect，修正 design.md 并重审；L1/L2 先升级一档，第二轮后升级 Sol `xhigh`。
- **B 任务过大**：拆成垂直 task，重新定义不重叠文件范围。
- **C 审查争议**：保留 FINDING 证据，出现争议即至少 L3 Reviewer；Leader 不口头推翻 Reviewer。
- **D 需求不清**：向用户提出一个具体决策问题，不让 Coder 猜。
- **E 测试失败**：先判断代码失败、测试失败、依赖失败或环境阻塞；L1 首次失败升 L2，L2 或第二次失败升 L3，复杂根因才启动 Tester。
- **F MR 状态异常**：绑定 MR 不存在、已关闭、已合并、目标分支不符或出现多个候选时停止，不自动新开 MR。
- **G 并发冲突**：串行化共享文件、push、review 和 merge；必要时重新 rebase，禁止强行覆盖他人提交。

## 重试和升级

每次重试必须携带真实 FINDING/测试错误，并改变一个可验证变量：文件范围、设计假设、测试输入、实现策略或模型/effort。仅重复 Prompt 不算重试。

- Coder 测试失败：最多修复 2 次；
- MR Review 不通过：修复 → 真实测试 → Review，最多 2 轮；
- L1 首次失败：升级 L2，保留原始测试证据；
- L2 首次失败、任意硬风险或审查争议：升级 L3 `Sol high/xhigh`；
- 三轮无进展、重大安全/并发/迁移风险或自动策略耗尽：Sol `max` Director 终裁；
- Director 也无法给出可验证结论：暂停并请求用户裁决。

## 并行

只有 task 的写入文件集合不相交、没有共享迁移/接口/配置且互不依赖时并行 spawn。Coder 可以并行，测试结果由 Leader 汇总；同一 change 的提交、MR 绑定、review、修复和 merge 必须串行。

## Director 输入和结论

Director 必须收到原需求、设计版本、每轮变更、测试证据、Reviewer FINDING、MR 状态、已尝试策略和剩余决策。只能输出：按最小修复继续、重新设计回到 Phase 1/2、标记环境阻塞，或暂停请求用户裁决。Director 的建议不能代替真实测试或 Reviewer 通过。
