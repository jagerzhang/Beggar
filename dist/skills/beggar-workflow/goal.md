## Goal Loop 执行规范

> **本文件描述 Goal Loop 模式的完整执行逻辑。当用户通过 `/beggar:goal` 启动时激活。**

### 核心概念

| 概念 | 定义 |
|------|------|
| **Goal** | 用户期望达到的最终状态，用自然语言描述 + 可验证验收标准 |
| **迭代（Iteration）** | 一轮完整的 pipeline 执行。首轮完整、后续精简 |
| **差距（Gap）** | 当前状态与 Goal 验收标准之间的差异 |
| **无进展（No Progress）** | 连续 N 轮迭代差距未缩小 |

### 流程概览

```
Phase 0 (目标定义) → 首轮完整 Pipeline (Phase 1-5) → Phase 6 (目标验证)
                                                          │
                                                    ┌─────┴─────┐
                                                    │ 目标达成？ │
                                                    └─────┬─────┘
                                                    是 ←──┤──→ 否
                                                    ↓         ↓
                                                归档完成   差距分析 → 生成新 tasks → 精简 Pipeline (Phase 3-4-6)
                                                                     ↑                            │
                                                                     └────────────────────────────┘
```

### Phase 0: 目标定义

#### Step 0.1: 需求澄清

如果目标模糊（如"让系统更快"、"代码更优雅"），通过对话澄清为可验证目标。
- **已安装 Superpowers**：调用 `Skill("brainstorming")` 进行需求探索
- **未安装 Superpowers**：Leader 自行通过对话澄清

> ⚠️ **写锚点（防脱轨）**：进入澄清对话前，执行 `python3 ${HOME}/.codebuddy/skills/beggar-workflow/beggar-state.py init --goal "<目标描述>"`（自动创建 `openspec/changes/goal-pending/goal-state.json`，初始化全部字段，`current_step` 设为 `0.1-clarification`）。
> **Step 0.2 生成正式 slug 时**，Leader 将 `goal-pending/` 重命名为 `goal-<slug>/`（`mv openspec/changes/goal-pending openspec/changes/goal-<slug>`），保持状态文件连续性。如果 `goal-state.json` 已存在（非 goal-pending），执行 `python3 ${HOME}/.codebuddy/skills/beggar-workflow/beggar-state.py step 0.1-clarification` 更新即可。
> **读锚点**：澄清期间每次收到用户回复，执行 `python3 ${HOME}/.codebuddy/skills/beggar-workflow/beggar-state.py get current_step` 确认值为 `0.1-clarification`，再继续澄清对话。禁止凭 context 记忆推断当前步骤。

**目标不可验证时的处理**：
如果 Leader 判断目标无法制定可执行的验收标准，主动提示用户：
```
⚠️ 该目标难以制定可执行的验收标准，建议：
1. 拆分为多个可验证的子目标
2. 明确具体度量（如"响应时间 < 200ms"）
3. 或使用 /beggar:start 走单次流程
```

**内嵌限制提取**：
如果用户在目标描述中包含轮次或时间限制语（如"最多 5 轮"、"10 分钟内"、"不超过 3 轮"），Leader 在澄清阶段自动提取并写入 goal.md frontmatter：
- `stop_after_turns`: 用户指定的轮次上限（取 min(stop_after_turns, max_iterations) 作为有效上限）
- `stop_after_minutes`: 用户指定的时间上限（分钟）

提取示例：
- "最多 5 轮内修好" → `stop_after_turns: 5`
- "10 分钟内完成" → `stop_after_minutes: 10`
- "最多 5 轮，每轮不超过 10 分钟" → `stop_after_turns: 5`, `stop_after_minutes: 50`（总时间）

> **与 Profile 配置的关系**：内嵌限制优先于 Profile 配置的 `max_iterations`。安全边界检查时取 `min(stop_after_turns, max_iterations)` 作为有效轮次上限。如果用户未指定内嵌限制，则使用 Profile 配置值。

#### Step 0.1.2: 快速启动模式（--fast）

> ⚠️ **写锚点**：进入快速模式前写入 `current_step: "0.1.2-fast-start"`。

当用户使用 `/beggar:goal --fast <目标描述>` 时，跳过澄清对话和配置向导，直接进入 pipeline：

**快速模式流程**：
```
Step 0.0: 加载 persona + 重入检测（保留，不可跳过）
Step 0.1.2: 使用标准 Profile 默认值，跳过澄清和配置向导
Step 0.2: 生成 goal.md（Leader 直接从目标描述提取验收标准）
Step 0.3: 初始化 goal-state.json
Step 0.5: 进入首轮 Pipeline（跳过 Step 0.4 Director 审定）
```

**快速模式适用场景**：
- 目标本身包含明确验收标准（如"让 `go test ./...` 全部通过"）
- 修复类任务（如"修复 issue #123"）
- 用户明确要求快速启动

**快速模式不适合**：
- 目标模糊（如"让系统更快"）→ Leader 提示用户用标准模式
- 安全关键任务 → Leader 提示用户用标准模式 + 严格 Profile

**快速模式安全保障**：
快速模式仍保留：安全边界检查（max_iterations / max_agent_calls / no_progress_limit / stop_after_*）、goal-evaluator 独立验证、状态锚定防脱轨。仅跳过：需求澄清、配置向导交互、Director 目标审定。

#### Step 0.1.1: 配置向导（运行参数 + Director 终审）

目标澄清完成后、生成 goal.md 之前，Leader 向用户展示配置选项。

> ⚠️ **必须使用以下模板原文输出，不得自行翻译或用英文重述**：Leader 展示配置向导时，必须逐字使用下方模板中的中文文本，包括表格、选项描述和提示语。禁止将"标准模式""严格模式""轻量模式"等替换为"Standard""Strict""Lite"，禁止将"适合大多数开发任务"等替换为英文描述。所有面向用户的交互文本必须使用中文。

> ⚠️ **写锚点（防脱轨）**：展示配置向导之前，执行 `python3 ${HOME}/.codebuddy/skills/beggar-workflow/beggar-state.py step 0.1.1-config`
> **读锚点**：收到用户配置选择后，执行 `python3 ${HOME}/.codebuddy/skills/beggar-workflow/beggar-state.py get current_step` 确认值为 `0.1.1-config`，再应用配置并继续。

```
📊 Goal Loop 配置

目标已明确，请选择运行配置：

  ┌─────────────────────────────────────────────────────────────────────┐
  │ 配置项                │ 标准  │ 严格  │ 轻量  │ 说明                │
  ├───────────────────────┼───────┼───────┼───────┼─────────────────────┤
  │ Director 终审         │  ❌   │  ✅   │  ❌   │ 达标后 Director 拍板 │
  │ 最大迭代轮数          │   8   │  12   │   5   │ 超出则暂停上升用户   │
  │ 最大 Agent 调用数     │  80   │  120  │  50   │ 超出则暂停上升用户   │
  │ 连续无进展上限        │   3   │   4   │   3   │ 超出则强制暂停       │
  │ 连续人工驳回上限      │   3   │   3   │   3   │ 超出触发 Director 介入 │
  └─────────────────────────────────────────────────────────────────────┘

  1. 📋 标准模式（默认）— 适合大多数开发任务
  2. 🛡️ 严格模式 — 启用 Director 终审，放宽迭代上限，适合安全关键/发布前验收
  3. ⚡ 轻量模式 — 快速迭代，适合小范围修复/简单重构
  4. ⚙️  自定义 — 逐项配置每个参数

  请选择 (1/2/3/4，默认 1):
```

**用户选择预设 Profile（1/2/3）时**，直接应用对应配置：

| 配置项 | 标准 | 严格 | 轻量 |
|--------|------|------|------|
| `director_final_review` | `false` | `true` | `false` |
| `max_iterations` | `8` | `12` | `5` |
| `max_agent_calls` | `80` | `120` | `50` |
| `no_progress_limit` | `3` | `4` | `3` |
| `human_reject_limit` | `3` | `3` | `3` |

**用户选择自定义（4）时**，Leader 逐项询问：

```
⚙️ 自定义配置

1. Director 终审: 启用后每轮达标额外调用 Director 确认（约 4-8K tokens/次）
   1) 启用  2) 不启用（默认）
   请选择:

2. 最大迭代轮数 (3-15，默认 8):
   > 

3. 最大 Agent 调用数 (20-150，默认 80):
   > 

4. 连续无进展上限 (1-5，默认 3):
   > 

5. 连续人工驳回上限 (1-5，默认 3):
   > 
```

用户输入后 Leader 校验范围，超出范围时提示重新输入。

**配置写入**：无论预设还是自定义，Leader 将最终配置值写入：
- goal.md frontmatter（`director_final_review`、`max_iterations`、`max_agent_calls`、`no_progress_limit`、`human_reject_limit`）
- goal-state.json（同上 5 个字段）

**用户跳过（直接回车）时**：应用标准模式默认值，不阻塞流程。

> **resume 恢复时**：从 goal-state.json 读取所有配置字段，无需重新询问。

#### Step 0.2: 生成 goal.md

```
读取 .codebuddy/persona-active.json（加载角色配置）
创建 openspec change:
  openspec/changes/goal-<slug>/
    ├── goal.md
    └── goal-state.json
```

> ⚠️ **change-id 一致性**：`goal-<slug>` 是整个 Goal Loop 的唯一 change-id。后续 Phase 1 的 architect、Phase 5 的 recorder、归档时的 `openspec archive` 都必须使用这个 change-id，不能让 architect 自行生成新名称。

> ⚠️ **配置值来源**：以下模板中 `max_iterations` / `max_agent_calls` / `no_progress_limit` / `director_final_review` / `human_reject_limit` 五个字段的**具体数值**，必须使用 Step 0.1.1 用户最终选择的配置（预设 Profile 或自定义输入），**不是**本模板展示的默认值。模板仅展示标准 Profile 的默认样例。

**goal.md 模板**（以下为标准 Profile 默认值示例，实际写入时替换为 Step 0.1.1 的选择结果）：
```markdown
---
max_iterations: 8
max_agent_calls: 80
no_progress_limit: 3
director_final_review: false
human_reject_limit: 3
stop_after_turns: null
stop_after_minutes: null
---

# Goal: <目标标题>

## 目标描述
<用户原始目标，澄清后的版本>

## 验收标准（必须可验证）
1. [可执行] <验收条件>
2. [可执行] <验收条件>
3. [可执行] <验收条件>

## 验收方式
- 自动验证: <tester agent 执行的命令/测试>
- 人工验证: <需用户确认的点，如有>

## 约束
- <技术约束>
- <范围约束>

## 预估迭代数
<Leader 评估>
```

**验收标准设计原则**：

| 原则 | 说明 | 示例 |
|------|------|------|
| 可执行 | 能用命令或测试验证 | `go test ./... 全部通过` ✅ |
| 二值判断 | 要么通过要么不通过 | `lint 零 error` ✅ |
| 覆盖核心路径 | 覆盖目标核心诉求，3-5 条 | 不要穷举 20 条 |
| 包含负向验证 | 验证不该出现的不再出现 | `grep -r "TODO" 返回 0` |

#### Step 0.3: 初始化 goal-state.json

在 Director 审定（Step 0.4）之前先初始化状态文件，确保后续所有 Agent 调用都能被正确计数：

> ⚠️ **配置值来源**：`max_iterations` / `max_agent_calls` / `no_progress_limit` / `director_final_review` / `human_reject_limit` 必须与 goal.md frontmatter 保持一致，均取自 Step 0.1.1 用户最终选择的配置。

执行 `python3 ${HOME}/.codebuddy/skills/beggar-workflow/beggar-state.py init --goal "<目标>" --max-iterations <N> --max-agent-calls <N> --human-reject-limit <N> [--director-final-review] [--stop-after-turns <N>] [--stop-after-minutes <N>] --force`（Step 0.1 已通过 init 创建了初始文件，此处用 `--force` 覆盖为正式配置。自动设置 `current_step` 为 `0.5-pipeline`，初始化全部字段含状态锁、计数器、时间戳）。

> **字段参考**（脚本自动生成，无需手动写入）：goal / status / current_step / current_iteration / max_iterations / max_agent_calls / agent_calls_used / no_progress_streak / human_reject_count / human_reject_limit / completed_steps / director_*系列 / evaluator_*系列 / stop_after_* / verification_results / created_at / updated_at

#### Step 0.4: Director 审定目标与验收标准

> **Director 调用模板**（适用于所有 Director 调用：Step 0.4 / 6.6.1 / 6.6.2 / 6.7）：
> ```
> Agent({
>   subagent_type: "director",
>   max_turns: 15,
>   prompt: "{roles.director}，<场景引导语>。\n\n完成后直接输出结果。\n\n---\n\n<场景化 prompt 正文>\n\n⚠️ 禁止使用 Agent 工具派生子 Agent，仅基于以上信息做判断。",
>   description: "{roles.director} <场景简述>"
> })
> ```
> 以下各 Step 仅列出每个场景的引导语和 prompt 正文差异部分。

> ⚠️ **Agent 调用计数**：目标定义阶段的所有 Agent 调用都计入安全边界，由「调用后置位」步骤统一递增 `agent_calls_used`。

> 🔒 **状态锁**：`director_target_review_done`。规则见 SKILL.md 规则 5.3.1。

目标定义和验收标准草拟完成后，Leader 调用 Director agent 做最终审定：

- **引导语**："有个目标需要您把把关"
- **prompt 正文**：
  ```
  ## 目标审定
  用户原始需求: <用户描述>
  澄清后目标: <澄清后目标>
  验收标准: <逐条列出>
  请审查：1.目标是否明确且可验证 2.验收标准是否覆盖核心路径 3.是否有遗漏的边界场景 4.预估迭代数是否合理
  输出: 【通过】或【需调整 + 具体建议】
  ```
- **description**："审定目标"

> **模型由 frontmatter 决定**：Director 的模型由 `director.md` frontmatter 的 `model` 字段决定，该字段在预设切换时由 `set_agent_model()` 自动写入（balanced/quality → claude-opus-4.7-1m，economic → claude-opus-4.6-1m）。**调用时不再传 `model` 参数**，避免与预设配置冲突。用户可通过 `beggar agent custom director <model>` 自定义。

> **调用后置位**：Director 返回后，执行 `python3 ${HOME}/.codebuddy/skills/beggar-workflow/beggar-state.py post-call --step "0.4" --agent "director" --lock director_target_review_done --task "目标审定"`（自动递增 agent_calls_used、设置状态锁、追加 dispatch log）。

> **成本说明**：Director 绑定 claude-opus-4.7-1m（最高级模型），但目标定义阶段仅调用 1 次，token 消耗可控（约几千 token）。目标定义的质量直接决定整个 Loop 的成败，这笔投入属于高杠杆决策。

#### Step 0.5: 进入首轮 Pipeline

首轮走完整 Phase 1→2→3→4→5（与 `/beggar:start` 完全相同）。

**⚠️ 关键差异 1 — change-id 传递**：Phase 1 调用 architect 时，必须在 prompt 中显式传入 Phase 0 已创建的 change-id，否则 architect 会自行生成新名称，导致产物分散在两个目录中。在标准 architect prompt 中追加：

```
请使用 change name `goal-<slug>` 执行 /opsx:propose（将 goal-<slug> 作为 /opsx:propose 的参数传入），确保所有 artifacts 生成在 openspec/changes/goal-<slug>/ 目录下。
```

**⚠️ 关键差异 2 — 迭代中不归档**：Goal Loop 迭代中，Phase 5 的 recorder 调用使用**修改版 prompt**，明确禁止 `openspec archive`：

```
Agent({
  subagent_type: "recorder",
  prompt: "{roles.recorder}，本轮迭代完成了，记一下档。\n\n完成后直接输出结果。\n\n---\n\n⚠️ 重要：当前处于 Goal Loop 迭代中，**不要执行 openspec archive**，保持 change 活跃。\n\n本轮归档：\n1. 记录本轮迭代的主要变更（不执行 archive）\n2. 更新 memory/coder-guard.json\n3. 记录本轮经验教训\n\n归档完成后等待 Phase 6 目标验证。",
  description: "{roles.recorder} 记档（不归档）",
  max_turns: 30
})
```

仅当 Phase 6 验证通过、目标达成时，才执行带 `openspec archive` 的标准归档（见「归档完成」章节）。

### Phase 6: 目标验证

> ⚠️ **Agent 调用计数**：Phase 6 中每次调用 Agent 工具（tester、reviewer、Director）后，Leader 必须递增 `goal-state.json` 中的 `agent_calls_used` 字段。安全边界检查依赖此计数。

#### Step 6.1: 读取验收标准

Leader 读取 `goal.md`，提取所有验收标准。

#### Step 6.2: 自动验证（tester agent）

调用 tester agent 执行 goal.md 中定义的命令和测试：

```
Agent({
  subagent_type: "tester",
  prompt: "{roles.tester}，目标定好了，你去验一下现在达标没有。\n\n完成后直接输出结果。\n\n---\n\n## 目标验证\n\n请逐条执行以下验收标准，输出每条的 PASS/FAIL 结果：\n\n<逐条列出 goal.md 中的验收标准>\n\n## 输出格式\n| # | 验收标准 | 结果 | 详情 |\n|---|---------|------|------|\n\n如果失败，说明具体失败原因和涉及的文件。",
  description: "{roles.tester} 验收目标",
  max_turns: 40
})
```

#### Step 6.3: 完整性审查（reviewer agent）

调用 reviewer agent 审查是否有遗漏：

```
Agent({
  subagent_type: "reviewer",
  prompt: "{roles.reviewer-a}，代码改完了，你帮忙看看有没有漏的。\n\n完成后直接输出结果。\n\n---\n\n## 完整性审查\n\n目标: <goal.md 中的目标描述>\n\n审查要点:\n1. 是否有遗漏的代码路径（检查所有相关文件）\n2. 是否有半成品（TODO/FIXME/未实现的函数）\n3. 跨任务一致性（不同文件的同类逻辑是否一致）\n4. 验收标准是否覆盖了所有代码变更\n\n输出: 【完整】或【有遗漏 + 具体问题列表】",
  description: "{roles.reviewer-a} 看有没有漏的",
  max_turns: 40
})
```

#### Step 6.4: 差距分析（reviewer agent — 禁止 Leader 自行执行）

> ⚠️ **条件执行**：仅当 Step 6.2 存在 FAIL 项或 Step 6.3 结论为【有遗漏】时才执行本步。若全部 PASS 且完整性审查通过，跳过本步直接进入 Step 6.5。

> ⚠️ **委派强制**：差距分析必须委派给 reviewer agent 执行，Leader 禁止自行 Grep/Read 源代码做分析。这确保分析结果来自独立 agent 的完整审查，而非 Leader 的零散片段检查。

调用 reviewer agent 执行差距分析：

```
Agent({
  subagent_type: "reviewer",
  prompt: "{roles.reviewer-a}，验证结果出来了，有差距，你来分析一下。\n\n完成后直接输出结果。\n\n---\n\n## 差距分析\n\n目标: <goal.md 中的目标描述>\n验收标准:\n<逐条列出>\n\ntester 验证结果: <Step 6.2 的 PASS/FAIL 详情>\nreviewer 完整性审查: <Step 6.3 的结论>\n\n请逐条分析未通过的验收标准：\n1. 差距类型（实现不完整/实现有误/验收标准遗漏/设计缺陷/方向错误）\n2. 根因分析（具体哪些文件/函数/逻辑缺失或错误）\n3. 修复建议（生成具体可执行的 task 描述，包含相关文件路径和行号）\n4. 建议分派的 coder 级别（lite/standard/senior）\n\n输出格式：\n| # | 验收标准 | 差距类型 | 根因 | 修复 task | coder 级别 |\n|---|---------|---------|------|----------|-----------|\n\n⚠️ 你的分析结果将直接作为下一轮迭代的 tasks，请确保每个 task 描述具体、可执行、有明确文件位置。",
  description: "{roles.reviewer-a} 分析差距",
  max_turns: 40
})
```

> **调用后置位**：reviewer 返回差距分析后，执行 `python3 ${HOME}/.codebuddy/skills/beggar-workflow/beggar-state.py post-call --step "6.4" --agent "reviewer" --task "差距分析"`（自动递增 agent_calls_used、追加 dispatch log）。

Leader 收到 reviewer 的差距分析后，将分析结果整理为 tasks 追加到 tasks.md（见「差距分析与迭代规划」章节），**不得自行补充或修改 reviewer 的分析结论**。如果 Leader 认为 reviewer 的分析有遗漏，应再调用一次 reviewer 补充分析，而非自行添加。

#### Step 6.5: 生成验证报告

Leader 将 tester、reviewer（完整性审查）、reviewer（差距分析）的结果汇总，存入 `iterations/iter-N.md`：

```markdown
## 📊 目标验证报告 — Iteration N

### 验收标准检查

| # | 验收标准 | 方式 | 结果 | 详情 |
|---|---------|------|------|------|
| 1 | go test ./... 全部通过 | tester | ✅ PASS | 42/42 通过 |
| 2 | curl /api/users 不含 deleted | tester | ❌ FAIL | 仍有 3 条 |
| 3 | lint 零 error | tester | ✅ PASS | 0 errors |
| 4 | 所有 CRUD 有 status 过滤 | reviewer 差距分析 | ❌ FAIL | endpoints.go 缺失 |

### 完整性审查
- reviewer 结论: 【有遗漏】
- 遗漏问题: endpoints.go List handler 未修改

### 差距分析（reviewer agent）
- 分析者: reviewer agent（独立审查）
- 差距类型: 实现不完整
- 根因: endpoints.go 的 List handler 未覆盖
- 修复 task: 修改 endpoints.go 添加 status 默认过滤
- 建议 coder: coder-standard

### 结论
⚠️ **有差距** — 4 条标准中 2 条未通过
```

#### Step 6.5.1: 独立判定（goal-evaluator agent — 禁止 Leader 自行判定）

> ⚠️ **委派强制**：目标是否达成的最终判定由独立的 goal-evaluator agent 执行，Leader 不得自行判定。这确保判定来自不参与执行的独立模型，避免"自己判自己"的偏差。

> 🔒 **状态锁**：`evaluator_done`。每轮迭代仅调用 1 次。规则见 SKILL.md 规则 5.3.1。

调用 goal-evaluator agent 做独立判定：

```
Agent({
  subagent_type: "goal-evaluator",
  prompt: "{roles.goal-evaluator}，验证报告都出来了，请你做独立判定。\n\n完成后直接输出结果。\n\n---\n\n## 目标验证独立判定\n\n目标: <goal.md 中的目标描述>\n\n验收标准:\n<逐条列出>\n\ntester 验证结果:\n<Step 6.2 的 PASS/FAIL 详情>\n\nreviewer 完整性审查:\n<Step 6.3 的结论>\n\nreviewer 差距分析:\n<Step 6.4 的结论，如有>\n\n请基于以上报告，判定目标是否达成。\n\n输出格式（严格 JSON）:\n{\n  \"verdict\": \"achieved\" 或 \"gap\",\n  \"reason\": \"一句话判定理由\",\n  \"failed_criteria\": [未通过的验收标准编号],\n  \"confidence\": \"high\" 或 \"medium\" 或 \"low\"\n}",
  description: "{roles.goal-evaluator} 独立判定",
  max_turns: 8
})
```

> **调用后置位**：goal-evaluator 返回后，执行 `python3 ${HOME}/.codebuddy/skills/beggar-workflow/beggar-state.py post-call --step "6.5.1" --agent "goal-evaluator" --lock evaluator_done --extra '{"evaluator_verdict":"<verdict>","evaluator_confidence":"<confidence>","evaluator_reason":"<reason>"}' --task "独立判定"`（自动递增 agent_calls_used、设置状态锁、写入判定字段、追加 dispatch log）。

> **模型独立性**：goal-evaluator 默认使用 claude-haiku-4.5（balanced/quality 预设）或 kimi-k2.5（economic 预设），确保与 Leader 模型不同，避免同模型自判。

#### Step 6.6: 判定与流转

> ⚠️ **Leader 不得覆盖 evaluator 判定**：以下流转基于 Step 6.5.1 goal-evaluator 的 `verdict`，Leader 不得自行修改判定结果。唯一例外：`confidence` 为 `low` 时，Leader 可上升 Director 裁决（Step 6.6.2）。

| evaluator verdict | confidence | 流转 |
|-------------------|------------|------|
| `"achieved"` | high/medium | → 检查 `director_final_review`：`true` → Step 6.7 Director 终审；`false` → 归档完成 |
| `"gap"` | high/medium | → 差距分析（Step 6.4 已有分析结果，直接生成新 tasks 进入迭代） |
| `"achieved"` 或 `"gap"` | low | → Step 6.6.2 Director 分歧裁决（信息不足，需 Director 介入） |

> ⚠️ **人工验证项**：如果 goal.md 验收方式中包含「人工验证」项，无论自动验证结果如何，Leader 必须：
> 1. 执行 `python3 ${HOME}/.codebuddy/skills/beggar-workflow/beggar-state.py step 6.6-human-verify`
> 2. 列出人工验证项请用户逐条确认，**等待用户回复**
> 3. 收到用户回复后执行 `python3 ${HOME}/.codebuddy/skills/beggar-workflow/beggar-state.py get current_step` 确认值为 `6.6-human-verify`，再继续处理
> 4. 用户确认通过 → 执行 `python3 ${HOME}/.codebuddy/skills/beggar-workflow/beggar-state.py set human_reject_count 0`，进入「达成」判定
> 5. 用户确认未通过 → 执行 `python3 ${HOME}/.codebuddy/skills/beggar-workflow/beggar-state.py set human_reject_count <当前值+1>`，按「有差距」处理。**若 `human_reject_count >= human_reject_limit`（默认 3 次），强制触发 Step 6.6.1 Director 介入（不进入常规差距分析）**。
> 6. **用户手动触发**：用户在任何一轮人工验证中回复包含 `director` / `终审` / `请 Director` / ` escalate` 等关键词时，**立即触发 Step 6.6.1 Director 介入**，不受 `human_reject_count` 阈值限制。Leader 检测到关键词后执行 `python3 ${HOME}/.codebuddy/skills/beggar-workflow/beggar-state.py set human_reject_count <human_reject_limit>`（确保状态一致），然后调用 Director。

#### Step 6.6.1: Director 介入（连续人工驳回触发）

> 🔒 **状态锁**：`human_director_done`。规则见 SKILL.md 规则 5.3.1。

> **触发条件**（满足任一）：
> - `human_reject_count >= human_reject_limit`（默认连续 3 次人工驳回）
> - 用户在人工验证中回复包含 `director` / `终审` / `请 Director` / `escalate` 等关键词（手动触发，不受阈值限制）

当用户连续驳回达到上限时，说明 Leader 与用户之间存在系统性认知偏差——Leader 认为已完成但用户持续不认可，常规差距分析无法解决。强制调用 Director 做全局根因分析：

- **引导语**："用户连续驳回 {human_reject_count} 次，需要您做全局根因分析"
- **prompt 正文**：
  ```
  ## 连续驳回根因分析
  目标: <goal.md 中的目标描述>
  验收标准: <逐条列出>
  ### 历次驳回详情: <每次驳回理由逐轮列出>
  ### 当前实现状态: tester结论/reviewer结论/goal-evaluator判定
  ### 关键代码变更: <历次迭代主要变更>
  ### 设计方案摘要: <核心设计决策>
  请分析：1.为什么Leader认为达成但用户不认可 2.验收标准是否模糊 3.实现方向是否偏了 4.模型组合是否无法满足
  输出格式(JSON): { classification, diagnosis, action, new_criteria[], tasks_hint[] }
  ```
- **description**："连续驳回根因分析"

> **Director 裁决分类**（复用 router.md 6 类分型）：

| 分类 | 根因 | 处理 |
|------|------|------|
| A - 方向错误 | 实现方向偏了，需修正 | Director 标注修正方向 → `human_reject_count` 归零 → 按修正方向生成新 tasks 进入迭代 |
| B - 验收标准模糊 | 标准过于笼统，Leader 与用户理解不一致 | Director 补充具体验收标准写入 goal.md → `human_reject_count` 归零 → 用新标准重新验证当前实现 |
| C - 需求歧义 | 原始需求有多重解读 | Director 列出需用户澄清的具体问题 → 暂停上升用户 |
| D - 能力天花板 | 当前模型组合确实做不到用户期望 | Director 建议切 quality 预设或手动接管 → 暂停上升用户 |
| E - 环境限制 | 缺少依赖/权限/配置导致无法满足 | Director 列出缺失项 → 暂停上升用户 |
| F - 误判 | Agent 实现其实可接受，用户驳回属误判 | Director 标注理由 → 向用户展示 Director 分析，请用户重新确认 |

> **调用后置位**：Director 返回后，执行 `python3 ${HOME}/.codebuddy/skills/beggar-workflow/beggar-state.py post-call --step "6.6.2" --agent "director" --lock human_director_done --extra '{"human_director_verdict":"<classification>"}' --task "连续驳回介入"`（自动递增 agent_calls_used、设置状态锁、写入裁决字段、追加 dispatch log）。

> ⚠️ **A/B 类自动恢复**：Director 给出 A/B 类裁决时，流程自动恢复——Leader 按建议生成新 tasks 进入迭代，不打断用户。`human_reject_count` 归零重新计数。
>
> ⚠️ **C/D/E/F 类上升用户**：Leader 向用户展示 Director 的完整分析结论，暂停流程等待用户决策。
>
> **通知(N6-voice)**: 如 notify 启用, PROJECT=$(basename "$PWD"); MSG="### [beggar] 🎯 Director 介入（连续驳回）\n\n> **项目**：\`$PROJECT\`\n> **裁决**: {分类} — {一句话结论}\n> **状态**: {自动恢复 / 需用户决策}"; beggar notify "$MSG" || true

#### Step 6.6.2: Director 终审（存在分歧时）

> 🔒 **状态锁**：`director_dispute_review_done`。规则见 SKILL.md 规则 5.3.1。

当 tester 和 reviewer 结论不一致，或 Leader 自检结果与前两者冲突时，调用 Director 做最终裁决：

- **引导语**："目标验证结果有分歧，需要您拍板"
- **prompt 正文**：
  ```
  ## 验证分歧裁决
  目标: <goal.md 中的目标描述>
  验收标准: <逐条列出>
  tester 结论: <PASS/FAIL 详情>
  reviewer 结论: <完整/有遗漏 详情>
  Leader 自检结论: <Grep/Read 结果>
  请综合三方结果判定：1.目标是否达成 2.如未达成差距类型 3.下一步建议
  输出: 【达成】或【有差距 + 差距类型 + 下轮 tasks 建议】
  ```
- **description**："终审验证"

> **调用后置位**：Director 返回后，执行 `python3 ${HOME}/.codebuddy/skills/beggar-workflow/beggar-state.py post-call --step "6.6.1" --agent "director" --lock director_dispute_review_done --extra '{"director_dispute_verdict":"<achieved或gap>"}' --task "分歧裁决"`（自动递增 agent_calls_used、设置状态锁、写入裁决字段、追加 dispatch log）。

> ⚠️ **与 Step 6.7 的互斥关系**：若 Step 6.6.2 已经调用过 Director 且 `director_dispute_verdict` 为 `"achieved"`，则本轮**不再**重复触发 Step 6.7 终审（同一轮不对同一个"达成"结论调用 Director 两次），直接视为已完成终审确认 → 归档完成。若 `director_dispute_verdict` 为 `"gap"`，则走差距分析，本轮不涉及 Step 6.7。resume 恢复时，Leader 从 `goal-state.json` 读取 `director_dispute_verdict` 判断是否跳过 Step 6.7，不依赖运行时记忆。

#### Step 6.7: Director 终审（director_final_review 启用时必经）

> 🔒 **状态锁**：`director_final_review_done`。规则见 SKILL.md 规则 5.3.1。

> **触发条件**：goal-state.json 中 `director_final_review` 为 `true`，且 Step 6.6 判定为"达成"，且本轮**未经过** Step 6.6.2 分歧裁决（若已经过 6.6.2 且结果为达成，跳过本步，直接归档）。

Leader 将目标定义、设计方案和验收结果打包汇报给 Director 做终审确认：

- **引导语**："目标验证全部通过了，最终请您确认一下是否可以收工"
- **prompt 正文**：
  ```
  ## Goal 终审
  ### 原始目标: <goal.md 中的目标描述>
  ### 验收标准与结果: <逐条列出 + tester/reviewer/Leader 三方验证结果>
  ### 设计方案摘要: <核心设计决策，2-3 句话>
  ### 关键代码变更: <主要变更文件和逻辑，5-10 行>
  ### 迭代历程: <共 N 轮，每轮一句话概述>
  请审查：1.验收标准是否覆盖目标 2.设计方案是否存在隐患 3.代码变更是否与设计一致 4.是否需归档前补充
  输出: 【通过】或【驳回 + 具体问题列表 + 建议差距类型】
  ```
- **description**："Goal 终审"

> **调用后置位**：Director 返回【通过】后，执行 `python3 ${HOME}/.codebuddy/skills/beggar-workflow/beggar-state.py post-call --step "6.7" --agent "director" --lock director_final_review_done --task "终审"`（自动递增 agent_calls_used、设置状态锁、追加 dispatch log）。若 Director 返回【驳回】，不在此处重置 `director_final_review_done`（下一轮迭代开始时的 `python3 ${HOME}/.codebuddy/skills/beggar-workflow/beggar-state.py reset` 会自动将其归零），然后进入差距分析。

Director 输出处理：

| Director 结论 | 处理 |
|--------------|------|
| 【通过】 | → 归档完成 |
| 【驳回】 | Leader 将驳回问题转化为新 tasks，按差距分析流程处理。差距类型取 Director 建议或默认"实现不完整" |

> **成本说明**：启用 `director_final_review` 后，每轮"Leader 判定达成"都会调用一次 Director。典型 2-3 轮迭代的 Goal Loop 中，Director 终审调用 1-3 次（可能前几次被驳回）。每次约 4-8K tokens（x3.33 倍率），总增量约 10-25%。Director max_turns 已限制为 15，禁止使用 Agent 工具派生子 Agent，避免 token 失控。

### 差距分析与迭代规划

#### 差距类型分型

| 类型 | 表现 | 应对 |
|------|------|------|
| 实现不完整 | 部分 task 未覆盖所有路径 | 生成新 task 补全 |
| 实现有误 | 代码写了但逻辑不对 | 生成修复 task，可能升级 coder |
| 验收标准遗漏 | 发现新需验证的点 | 补充 goal.md，重新验证 |
| 设计缺陷 | 方案本身有问题 | **递增 `design_revisions_used`**，回到 Phase 1 重新设计。`design_revisions_used` 已达 1 时不允许再回 Phase 1，改为暂停上升用户 |
| 方向错误 | 整体方向不对 | 暂停，上升用户 |

#### 生成新一轮 tasks

Leader 将差距转化为新 tasks，追加到 tasks.md。**进入差距分析前先写 `current_step: "iterating"`**：

```markdown
## Iteration N Tasks（差距修复）

- [ ] Task X: <任务描述>
  - 标签: <标签>
  - 相关文件: <file:line>
  - 参照: <参照代码位置>
  - 设计要求: <设计要求>
```

#### 精简 Pipeline

后续迭代走精简版（跳过 Phase 1-2）：

```
差距分析 → 生成 tasks → Phase 3（编码+测试+审查）→ Phase 4（终审）→ Phase 6（目标验证）
```

> ⚠️ **委派门禁检查（进入精简 Pipeline 前）**：Leader 在开始新一轮迭代前必须自检：
> 1. 读取 `agent_dispatch.log`，确认上一轮有 coder + tester + reviewer 的调用记录
> 2. 如果上一轮的 dispatch 记录少于 3 条（缺少 coder/tester/reviewer 任一）→ **异常**，说明上一轮 Leader 退化为主力，暂停并向用户报告
> 3. 确认本轮即将执行的第一个操作是调用 `Agent` 工具分派 coder，而非 Leader 自行 Read/Write/Edit
> 4. 执行 `python3 ${HOME}/.codebuddy/skills/beggar-workflow/beggar-state.py step iterating`

> ⚠️ **迭代计数与状态锁重置**：进入精简 Pipeline 前，执行 `python3 ${HOME}/.codebuddy/skills/beggar-workflow/beggar-state.py reset`（自动递增 `current_iteration` 并重置单轮状态锁），然后执行 `python3 ${HOME}/.codebuddy/skills/beggar-workflow/beggar-state.py check` 做安全边界检查。首轮 pipeline 的 `current_iteration` 为 0，第一次差距修复迭代开始时递增为 1。

**例外**：差距类型为"设计缺陷"时，回到 Phase 1 走完整 pipeline。

> ⚠️ **迭代 tasks 仍遵循 router.md**：差距分析生成的新 tasks 必须走标准分派流程——打标签 → 查 Coder Guard → 分级分派。不能因为"是修复任务"就跳级或跳过降级保护检查。

### 安全边界

#### 每轮迭代后必须检查

执行 `python3 ${HOME}/.codebuddy/skills/beggar-workflow/beggar-state.py check`（自动检查以下全部条件，返回 JSON 结果）：

1. `current_iteration ≥ max_iterations?` → 暂停，向用户报告进展和剩余差距 (N9-voice)
2. `agent_calls_used ≥ max_agent_calls?` → 暂停，向用户报告预算消耗 (N9-voice)
3. `no_progress_streak ≥ no_progress_limit?` → 暂停，向用户报告阻塞点 (N4-voice)
4. `stop_after_turns ≠ null 且 current_iteration ≥ stop_after_turns?` → 暂停，向用户报告"已达到用户指定的轮次上限" (N9-voice)
5. `stop_after_minutes ≠ null 且已运行时间 ≥ stop_after_minutes?` → 暂停，向用户报告"已达到用户指定的时间上限" (N9-voice)（已运行时间 = 当前时间 - goal-state.json.created_at）
6. `context 接近用满?` → 建议用户 /clear + /beggar:goal resume
7. `human_reject_count >= human_reject_limit?` → 强制触发 Step 6.6.1 Director 介入（不暂停，自动调用 Director 做根因分析）（默认 human_reject_limit=3）

> 脚本退出码 0 = 全部通过可继续，退出码 2 = 存在需暂停项（results 中含 action 字段的具体处理建议）。

> ⚠️ **每轮迭代开始时重置单轮状态锁**：进入新一轮精简 Pipeline 前，执行 `python3 ${HOME}/.codebuddy/skills/beggar-workflow/beggar-state.py reset`（自动递增 `current_iteration`、重置 9 个单轮状态锁、清空 `completed_steps`）。保留不动：`director_target_review_done`（全局一次性操作）、`human_reject_count`（跨迭代持久化，仅在用户确认通过或 Director 给出 A/B 类自动恢复策略时归零）。详见「精简 Pipeline」章节的 reset 说明。

#### 无进展判定

```
有进展（满足任一）：
- 新 tasks 全部通过 tester + reviewer
- 验收标准 PASS 数量增加
- 代码变更量 > 0 且通过验证

无进展（满足全部）：
- 新 tasks 未通过
- 验收标准 PASS 数量未增加
- 代码无有效变更
```

连续 `no_progress_limit` 轮无进展 → 强制上升用户裁决。

#### Agent max_turns 超限恢复

> 适用 SKILL.md 规则 1 中定义的通用恢复流程（检查产物 → 续作唤起 ×2 → 兜底翻倍 → 暂停上升用户）。所有 Agent 调用均适用。续作唤起不受 `completed_steps` 限制，但每次续作仍计入 `agent_calls_used`。

#### 更新 goal-state.json

每轮迭代后使用 `python3 ${HOME}/.codebuddy/skills/beggar-workflow/beggar-state.py set` 更新状态字段：
- `python3 ${HOME}/.codebuddy/skills/beggar-workflow/beggar-state.py set no_progress_streak <0或N>`（有进展设 0，无进展递增）
- `python3 ${HOME}/.codebuddy/skills/beggar-workflow/beggar-state.py set verification_results '<JSON数组>'`（追加本轮验证结果，含 iteration/passed/failed/verdict/gap_type）
- `agent_calls_used` 和 `current_iteration` 已由 `post-call` 和 `reset` 自动管理，无需手动更新

### 归档完成

当目标验证通过时：

1. 执行 `python3 ${HOME}/.codebuddy/skills/beggar-workflow/beggar-state.py achieve`（自动设置 status=achieved, current_step=achieved）
2. 调用 recorder agent 归档：
   ```
   Agent({
     subagent_type: "recorder",
     prompt: "{roles.recorder}，目标达成了，记一下档。\n\n完成后直接输出结果。\n\n---\n\n归档本次 Goal Loop：\n\n1. 执行 openspec archive goal-<slug> -y\n2. 记录迭代历程（共 N 轮，每轮主要变更）\n3. 更新 memory/coder-guard.json\n4. 总结经验教训",
     description: "{roles.recorder} 记下档",
     max_turns: 30
   })
   ```

3. **通知(N11-markdown)**: 如 notify 启用：
   ```bash
   PROJECT=$(basename "$PWD")
   MSG="### [beggar] 🎯 Goal 达成\n\n> **项目**：\`$PROJECT`\n> **详情**：经过 {N} 轮迭代，目标已达成并归档\n\n请回到对话查看"
   beggar notify "$MSG" || true
   ```

### 状态恢复

当用户执行 `/beggar:goal resume` 时：

1. 查找活跃的 goal change：执行 `python3 ${HOME}/.codebuddy/skills/beggar-workflow/beggar-state.py find`（返回 JSON，包含 path 和 type）

2. **多个活跃 goal 的处理**：
   如果找到多个 goal-state.json，Leader 列出所有活跃 goal 供用户选择：
   ```
   找到多个活跃 Goal Loop，请选择要恢复的：
   1. goal-<slug-A>: <目标描述>（第 N 轮，状态: in_progress）
   2. goal-<slug-B>: <目标描述>（第 M 轮，状态: in_progress）
   ```
   用户选择后，读取对应的 goal-state.json 恢复状态。如果只有 1 个，直接恢复。

3. 读取 goal-state.json 恢复状态

4. 输出状态摘要：
   ```
   📊 Goal Loop 恢复
   - 目标: <goal 描述>
   - 当前步骤: <current_step>（如 "0.1-clarification" / "0.5-pipeline" / "6-verification" / "iterating"）
   - 运行配置: Director 终审 <启用/未启用>，最大迭代 X 轮，最大调用 Y 次，无进展上限 Z 轮
   - 当前迭代: 第 N 轮
   - 已用 agent 调用: X/Y（Y 为当前 Profile 的 max_agent_calls）
   - Director 审定: <已完成/待执行>
   - 上轮结果: <gap/achieved>
   - 继续: <下一步动作>
   ```

5. 从中断点继续执行