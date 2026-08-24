---
name: beggar-brainstorming
description: Beggar for Codex 的 Phase 1 需求探索与澄清。Leader 只对齐目标、范围和验收标准，Architect 负责方案和 trade-off；适合需求模糊、边界不清或验收标准缺失的开发请求。
metadata:
  runtime: codex-native
---

# Beggar 需求探索与澄清

## 原则

- 一次只问一个用户决策问题；
- 每个问题给出基于当前事实的推荐答案；
- 能通过代码库、codegraph 或现有文档确认的事实，不向用户提问；
- 只澄清“做什么、为谁做、怎样算完成、边界是什么”，不替 Architect 决定“怎么实现”；
- 达到约 95% 理解就停止，不为穷尽细节而拖慢流程；
- 用 YAGNI 裁剪非必要范围。

## 流程

1. 先读取项目事实：涉及符号关系时优先使用通用 `codegraph query/callers/callees/impact/explore`，失败后使用 `rg` 和文件读取。
2. 判断需求是否已有明确目标、范围、验收标准；清晰则直接产出摘要，不提问。
3. 模糊时每轮只问一个决策问题，并附推荐答案；用户确认后继续下一项。
4. 将术语记录到 `CONTEXT.md`，将用户确认的需求决策记录为轻量 ADR。
5. 收敛后自动进入 Architect，不需要额外确认门禁。

## 产出格式

```markdown
## 需求摘要
- **目标**：
- **范围**：
- **不在范围内**：
- **验收标准**：
- **约束**：
- **关键决策**：
```

ADR 只记录用户确认的“做什么”，架构取舍由 Architect 在 design.md 记录。摘要、CONTEXT 和 ADR 通过 Prompt 传给 Architect；不要在 Leader 侧直接修改业务代码。
