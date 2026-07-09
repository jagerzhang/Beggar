---
name: BEGGAR: Goal
description: "启动目标驱动的循环工程模式。设定目标 → 执行 → 验证 → 迭代直到达标"
argument-hint: "[--fast] <目标描述>"
---

触发 Goal Loop 工程模式。

**触发**：用户输入 `/beggar:goal <目标描述>`，例如：
- `/beggar:goal 让所有 List 接口默认过滤已删除记录`
- `/beggar:goal 修复支付模块所有已知 bug 并通过全量测试`
- `/beggar:goal --fast 让 go test ./... 全部通过`（快速启动，跳过澄清和配置向导）
- `/beggar:goal resume`（恢复中断的 Goal Loop）

## 快速启动模式（--fast）

`/beggar:goal --fast <目标描述>` 跳过需求澄清和配置向导，使用标准 Profile 默认值直接进入 pipeline。适合目标本身包含明确验收标准的场景。仍保留安全边界检查、goal-evaluator 独立验证和状态锚定防脱轨。

## ⚠️ 启动前：重入检测（必须优先执行）

**在任何步骤之前**，Leader 必须先执行重入检测：

```bash
# 循环查找活跃的 goal-state.json（避免多个 goal 目录导致 cat 拼接无效 JSON）
for f in openspec/changes/goal-*/goal-state.json; do
  grep -q 'in_progress' "$f" 2>/dev/null && cat "$f" && break
done
```

| 检测结果 | 处理方式 |
|---------|---------|
| 文件存在且 `status == "in_progress"` | **自动按 resume 流程处理**，从 `current_step` 定位中断位置，不重走 Phase 0 |
| 文件存在且 `status == "achieved"` | 告知用户目标已完成，询问是否启动新 goal |
| 文件不存在 / 用户明确传入新目标 | 正常走 Phase 0 目标定义 |

> **目的**：防止 Leader 因 context 稀释忘记正在进行的 goal，重复发起 Phase 0 或退化为普通对话。

## ⚠️ 运行中：状态锚定规则（必须遵守）

Goal Loop 涉及多轮用户交互（澄清、配置选择、人工验证），**每次等待用户回复前必须写锚点，每次收到用户回复后必须读锚点**，防止 context 稀释导致脱轨。

**详细规则见 `SKILL.md` 规则 5**。简要：
- 等待用户输入前 → 写 `goal-state.json` 的 `current_step` 字段
- 收到用户回复后 → 先 `cat goal-state.json` 确认 `current_step`，再继续执行
- 禁止仅凭 context 记忆推断当前步骤

**步骤**：

0. **加载角色配置（硬门禁 — 必须在输出任何文字前执行）**
   ```bash
   cat .codebuddy/persona-active.json 2>/dev/null || cat ~/.codebuddy/persona-active.json 2>/dev/null
   ```
   - 读取成功 → 使用该主题的 greeting 和 roles 映射
   - 文件不存在 → 使用 default 专业主题，不得编造角色名
   - **禁止**：未读取配置就编造"老叫花""七公"等丐帮角色名

1. **加载 beggar-workflow skill**
   立即调用 `Skill("beggar-workflow")`，按 skill 中定义的阶段流程执行。

2. **Phase 0: 目标定义**
   - 澄清目标（如需要，调用 brainstorming）；澄清期间写 `current_step: "0.1-clarification"`
   - **配置向导**：选择运行 Profile（标准/严格/轻量/自定义）；展示前写 `current_step: "0.1.1-config"`
   - 生成 goal.md（含可验证验收标准 + 配置项）
   - 创建 openspec change (goal-<slug>)
   - 初始化 goal-state.json（含 `current_step: "0.5-pipeline"`）

3. **首轮执行（完整 Pipeline）**
   走完整 Phase 1→2→3→4→5 pipeline（与 /beggar:start 相同）
   - Phase 5 归档时**不执行** `openspec archive`，保持 change 活跃
   - pipeline 启动后写 `current_step: "0.5-pipeline"`

4. **Phase 6: 目标验证**
   - 写 `current_step: "6-verification"`
   - 读取 goal.md 验收标准
   - 调用 tester agent 执行自动验证
   - 调用 reviewer agent 审查完整性
   - 差距分析（委派 reviewer agent，禁止 Leader 自行 Grep）
   - 生成验证报告（存入 iterations/iter-N.md）
   - 如有**人工验证项**，写 `current_step: "6.6-human-verify"` 后等待用户逐条确认
   - **Director 终审**（如 `director_final_review: true`）：Leader 判定达成后，调用 Director 做终审确认，通过才归档

5. **迭代循环**
   - 验证通过 → 归档完成（执行 openspec archive），写 `current_step: "achieved"`
   - 验证不通过 → 写 `current_step: "iterating"` → 差距分析 → 生成新 tasks → 精简 pipeline（Phase 3→4→6）→ 回到步骤 4
   - 触发安全边界 → 暂停，上升用户裁决

6. **安全边界检查**（每轮迭代后，具体数值以 goal-state.json 中配置为准）
   - 最大迭代数: 默认 8（标准 Profile），超出暂停上升用户
   - 最大 agent 调用数: 默认 80（标准 Profile），超出暂停上升用户
   - 连续无进展上限: 默认 3（标准 Profile），超出强制暂停
   - context 接近用满 → 建议 `/clear` + `/beggar:goal resume`

7. **状态持久化**
   每轮迭代后更新 goal-state.json（含 `current_step`），支持跨 context 恢复。

---

**与 /beggar:start 的区别**：
- /beggar:start: 单次 pipeline，跑完结束
- /beggar:goal: 循环 pipeline，达标为止

**适用场景**：
- 目标明确但实现路径不确定（需要多轮探索）
- 修复类任务（修一个 bug 可能发现更多关联问题）
- 重构类任务（分多轮逐步改善）
- 需要验证标准明确的批量改造

**不适用场景**：
- 需求明确的单次开发（用 /beggar:start）
- 纯文档/配置修改（直接执行）
- 目标无法制定可执行验收标准（Leader 会提示）

**完整设计文档**：`docs/plans/2026-07-02-goal-loop-design.md`
**执行规范**：`skills/beggar-workflow/goal.md`
