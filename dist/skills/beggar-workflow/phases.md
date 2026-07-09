## 研发阶段流程

整体流程：用户需求 → Phase 1 方案设计 → Phase 2 方案评审 → Phase 3 代码开发 → Phase 4 最终审查 → Phase 5 归档沉淀

> **Goal Loop 模式**：`/beggar:goal` 在标准流程外层包一个目标驱动宏循环，新增 Phase 0（目标定义）和 Phase 6（目标验证）。首轮走完整 Phase 1-5，后续迭代走精简版。完整执行规范见 `goal.md`。

| Phase | Agent | 动作 | 产物 | 流转 |
|-------|-------|------|------|------|
| **Phase 0: 目标定义**（仅 Goal Loop） | Leader | 澄清目标 → 生成 goal.md + goal-state.json | goal.md + goal-state.json | → Phase 1（首轮）|
| **Phase 1: 方案设计** | architect | `/opsx:propose` | proposal.md + design.md + specs/ + tasks.md | → Phase 2 |
| **Phase 2: 方案评审**（多轮闭环） | reviewer（可多 reviewer 并行） | 审查 proposal + design + specs | gate-review.md（通过/驳回+具体修改要求） | 通过 → Phase 3；驳回 → 退回 Phase 1 修正后重新评审（最多 3 轮） |
| **Phase 3: 代码开发**（分级分派） | coder-lite/standard/senior + tester + reviewer | Per Task：coder 实现 → tester 验证 → reviewer 审查 | 代码变更 + tasks.md 标记完成 | Review Gate 不通过 → 升级 coder 重做 |
| **Phase 4: 最终审查** | reviewer | 全量 diff 审查 | 审查报告 | 通过 → Phase 5；不通过 → 退回修改 |
| **Phase 5: 归档沉淀** | recorder | `openspec archive` + 经验记录 | 归档完成 + memory 更新 | 单次模式 → 结束；Goal Loop → Phase 6 |
| **Phase 6: 目标验证**（仅 Goal Loop） | tester + reviewer + Leader | 验收标准检查 + 完整性审查 | 验证报告 (iterations/iter-N.md) | 达标 → 归档完成；未达标 → 差距分析 → Phase 3 |

**Phase 2 多 reviewer 模式（quality 预设）**：2 个 reviewer 并行评审（不同模型/视角），两者都通过才算通过。

**Phase 3 Per Task 链路**：Leader 判断复杂度 → 分派对应 coder → coder 实现+自测 → tester 编译+测试验证 → reviewer spec 合规+代码质量审查。

## 防重复调用机制（completed_steps 状态锁）

> ⚠️ **Goal Loop 模式注意**：当通过 `/beggar:goal` 启动时，本节所有对 `start-state.json` 的引用均应替换为 `goal-state.json`，路径为 `openspec/changes/goal-<slug>/goal-state.json`。`completed_steps` 命名规则也有差异（见本节末尾「Goal Loop 命名规则」）。

> ⚠️ **核心规则**：Leader 调用任何 Agent 前，必须先检查 `start-state.json` 中 `completed_steps` 数组是否包含该步骤标识。如果已存在，**跳过调用**，直接使用已有产物。调用完成后（Agent 返回结果），Leader 必须将步骤标识追加到 `completed_steps` 数组、递增 `agent_calls_used`、向 `agent_dispatch.log` 追加记录，写回 `start-state.json`。
>
> **步骤标识命名规则**：
> - Step 2 architect → `2-architect`
> - Step 3 reviewer-A（按轮次）→ `3-reviewer-a-r<round>`（如 `3-reviewer-a-r1`、`3-reviewer-a-r2`）
> - Step 3 reviewer-B（按轮次）→ `3-reviewer-b-r<round>`
> - Step 4.1 coder（按级别+任务）→ `4.1-coder-<level>-task<N>`（如 `4.1-coder-lite-task1`）
> - Step 4.2 tester（按任务）→ `4.2-tester-task<N>`
> - Step 4.3 reviewer（按任务）→ `4.3-reviewer-task<N>`
> - Step 5 reviewer → `5-reviewer`
> - Step 6 recorder → `6-recorder`
>
> **续作唤起例外**：max_turns 超限后的续作唤起不受 `completed_steps` 限制（因为上一次调用未正常返回），但续作唤起前必须先执行产物检查。
>
> **路径**：`openspec/changes/<change-id>/start-state.json`

> ⚠️ **Goal Loop 命名规则**：当通过 `/beggar:goal` 启动时，`completed_steps` 的步骤标识前缀需加上迭代号，格式为 `<iteration>-<step>-<agent>`（如 `0-2-architect`、`1-4.1-coder-lite-task1`）。详见 goal.md「completed_steps 防重复调用」章节。状态文件路径为 `openspec/changes/goal-<slug>/goal-state.json`。

## Superpowers Skills 集成

| 阶段 | 引用的 Superpowers Skill | 用途 |
|------|------------------------|------|
| Step 1 | `superpowers:brainstorming` | 需求不清晰时先头脑风暴 |
| Step 2 | `superpowers:writing-plans` | 方案设计的结构化方法 |
| Step 3 | `superpowers:subagent-driven-development` | Per-task 的实现+审查循环 |
| Step 3 | `superpowers:test-driven-development` | coder 编码时遵循 TDD |
| Step 3 (bug) | `superpowers:systematic-debugging` | 修复 bug 时先定位根因 |
| Step 4 | `superpowers:requesting-code-review` | 最终审查的模板和标准 |
| Step 4 | `superpowers:verification-before-completion` | 审查前必须运行验证 |
| Step 5 | `superpowers:finishing-a-development-branch` | 归档前的分支集成决策 |

## Superpowers 与多 Agent 的关系

**Superpowers** 提供研发质量实践（TDD、系统调试、代码审查等），**多 Agent 系统**提供执行架构（谁来执行、用什么模型）。两者是互补关系：

- Superpowers 回答"怎么做才对"（方法论）
- 多 Agent 系统回答"谁来做最省"（成本优化）

当使用 `/beggar:start` 时，Leader 会自动在适当时机调用 Superpowers skills 注入质量实践，同时通过分级 coder 控制成本。

### Superpowers 安装检查

在执行工作流前，检查 Superpowers 是否已安装：

```bash
# 检查是否已安装
ls $HOME/.codebuddy/plugins/marketplaces/codebuddy-plugins-official/external_plugins/superpowers/skills/ 2>/dev/null

# 如未安装，提示用户
# "Superpowers 插件未安装，建议安装以获得完整的质量实践支持：
#  在 CodeBuddy Code 中执行 /plugin superpowers"
```

## 通知调度（可选，基于群机器人 webhook）

如果 notify.json 存在且 `enabled: true`，Leader 在关键节点发送通知。

**优先级**：项目 `.codebuddy/notify.json` > 全局 `~/.codebuddy/notify.json`。
如果项目中有配置则用项目的，没有则自动降级到全局配置。两者都没有则跳过通知。

### 初始化（Step 1）

Leader 启动时读取 notify.json（`.codebuddy/notify.json` → fallback `~/.codebuddy/notify.json`）:
- 不存在或 enabled=false → 跳过所有通知
- enabled=true → 侧加载 token + channels + events 配置

### 调度规则

1. 检查 events.Nx.enabled 开关
2. 确定通知类别: events.Nx.channels_override（不为 null） or channels.\<category\>
3. 按渠道列表顺序调用: `beggar notify "<message>"`
4. `sendto` 从 notify.json 的 `sendTo` 字段读取
5. 任一成功 (exit 0) 停止，全部失败 `|| true` 静默忽略

### 渠道映射

| 渠道 | 说明 |
|------|------|
| wecom_cs_markdown | 唯一渠道，发送到企业微信客服号 |

### 变量来源表

Leader 构造消息模板变量时，从以下位置获取值：

| 变量 | 来源 | 示例 |
|------|------|------|
| `{change_id}` | openspec changes/ 目录名 | `beggar-notifications` |
| `{task_id}` | tasks.md 当前 task 编号 | `Task 3` |
| `{round_count}` | 循环计数器 | `3` (升级轮次3) |
| `{done}` / `{total}` | tasks.md [x] 和 [ ] 计数 | `4/6` |
| `{count}` | 阻塞项计数器 (N9) | `3` (3个问题需裁决) |
| `{duration}` | Phase 开始/结束时间差 | `12m` |

## 执行步骤

### Step 0: 加载角色 Persona（每次流程启动时必做）

**Leader 必须在流程开始时读取角色配置，后续所有 Agent 调用都使用角色名。**

```
读取 .codebuddy/persona-active.json，获取：
- greeting: Leader 的称呼（如 tech-legends → "Linus"，beggar-gang → "七公"）
- roles: 各 agent 的角色名映射（如 tech-legends 主题下 coder-senior → "Jeff Dean"，beggar-gang 主题下 → "乔峰"）
- report_templates: 汇报模板

如果文件不存在，使用默认专业名称（architect/coder-senior/...）。
**禁止**：未读取 persona-active.json 就编造角色名（如根据项目名"beggar"联想丐帮角色）。
```

### 角色化调度用语

当已启用角色主题（persona-active.json 存在）时，Leader 在调度 Agent 时应使用**自然的角色化语言**，避免生硬的"调用 XX"句式：

| 生硬写法 ❌ | 自然写法 ✅ |
|------------|-----------|
| "我来调用{roles.architect}" | "让{roles.architect}先看看这个需求" |
| "调动{roles.coder-senior}去实现" | "{roles.coder-senior}，你去把这事儿办了" |
| "启动{roles.director}审查" | "请{roles.director}过目一下代码" |
| "让{roles.reviewer-b}一起看看" | "{roles.reviewer-b}你也看看，有没有疏漏" |
| "调用{roles.coder-standard}来写" | "{roles.coder-standard}，这段代码你来写" |
| "使用{roles.tester}验证" | "{roles.tester}，去试试能不能跑通" |

**核心原则**：
1. **用对话语气**，别用命令/调用口吻。想象你是在跟兄弟/下属说话，不是在操作机器。
2. **融入角色关系**：读取 `persona-active.json` 中的 `roles` 映射，用实际角色名代入，如 `{roles.architect}` → "诸葛亮"（三国主题）或 "Dennis Ritchie"（Tech Legends 主题）。
3. **description 也要自然**：不要写"{roles.coder-senior} 实现 Task 1"，写"{roles.coder-senior} 去实现批量删除"、"{roles.architect} 出个方案"、"{roles.director} 审一下代码"

**Agent prompt 中的角色注入也保持一致**：
```
// 生硬 ❌
Agent({
  // 没有 subagent_type，会用 Leader 的模型运行！
  prompt: "你是「{roles.coder-senior}」(coder-senior agent)。{motto}。完成后直接输出结果。"
})

// 自然 ✅  
Agent({
  subagent_type: "coder-senior",  // 强制使用 coder-senior 绑定的 deepseek-v4-pro
  prompt: "{roles.coder-senior}听令！{motto}。{greeting}让你去搞定这件事：...",
  description: "{roles.coder-senior} 去查日志"
})
```

### Step 1: 初始化

1. **加载 Persona**（读取 `.codebuddy/persona-active.json`）

2. **需求澄清**（调用 Superpowers brainstorming）
   - 如果需求模糊、边界不清、用户只说"做个 xxx 功能"：
     - **已安装 Superpowers**：调用 `Skill("brainstorming")` 进行需求探索
     - **未安装 Superpowers**：Leader 自行通过对话澄清需求（一问一答方式）
   - 输出：清晰的需求描述 + 验收标准

3. 检查当前模型预设（`beggar show`）

   注意：全局安装模式下，所有项目默认共用 `~/.codebuddy/` 下的配置。如需某个项目使用自定义配置，可在项目中放置同名文件覆盖全局配置：
   - **Agent 模型**：在项目 `.codebuddy/agents/` 下放同名 `.md` 文件，CodeBuddy 自动优先使用项目级
   - **通知接收人**：在项目 `.codebuddy/notify.json` 中配置，覆盖全局通知设置
   - **角色主题**：在项目 `.codebuddy/persona-active.json` 中选择不同主题
   - **优先级规则**：项目级 > 全局 `~/.codebuddy/`

4. 加载通知配置（如存在且启用，则导出环境变量供后续通知使用）
   ```bash
   eval $(bash ${HOME}/.codebuddy/skills/beggar-notify/load-env.sh 2>/dev/null) || eval $(bash .codebuddy/skills/beggar-notify/load-env.sh 2>/dev/null) || true
   ```
   - 加载后 `$BEGGAR_NOTIFY_TOKEN` 和 `$BEGGAR_NOTIFY_SENDTO` 可用
   - 通知调用：`beggar notify "<message>" || true`
   - **消息格式规范**：所有通知统一使用 markdown，包含项目名（当前目录 basename）
     ```
     ### [beggar] <emoji> <标题>
     
     > **项目**：`<project>`
     > **详情**：<描述>
     
     <行动指引>
     ```
     示例：
     ```bash
     PROJECT=$(basename "$PWD")
     MSG="### [beggar] ✅ Phase 2 评审通过\n\n> **项目**：\`$PROJECT\`\n> **详情**：评审通过，进入代码开发阶段\n\n请回到对话查看"
     beggar notify "$MSG" || true
     ```

5. 创建 openspec change

### Step 2: 方案设计（architect agent）

> ⚠️ **防重复调用（状态锁）**：调用前先检查 `start-state.json` 中 `completed_steps` 是否已包含 `2-architect`。如果已存在，**跳过本步**，直接使用已有方案产物。
>
> **调用后置位**：Agent 返回后，执行 `python3 ${HOME}/.codebuddy/skills/beggar-workflow/beggar-state.py post-call --step "2" --agent "architect" --step-id "2-architect" --task "方案设计"`（自动递增 agent_calls_used、追加 completed_steps、追加 dispatch log）。

**前置**：调用 `superpowers:writing-plans` 获取计划编写方法论。

**⚡ 必须使用 Agent 工具调用 architect（角色化语言）：**
```
Agent({
  subagent_type: "architect",
  prompt: "{roles.architect}，{motto}。{greeting}让你为以下需求出个方案。\n\n完成后直接输出结果。\n\n---\n\n<需求描述>\n\n请执行 /opsx:propose 生成完整的 openspec artifacts（proposal.md + design.md + specs/ + tasks.md）。",
  description: "{roles.architect} 出个方案",
  max_turns: 80
})
```

Leader 收到 architect 返回的方案后，确认产物存在再进入下一步。

> 🔄 **architect max_turns 超限恢复**：适用 SKILL.md 规则 1 通用恢复流程。检查 `openspec/changes/<change-id>/` 下已产出文件（proposal.md / design.md / specs/ / tasks.md），续作唤起时注入已有产物列表。

### Step 3: 方案评审（双 reviewer 并行 — 闭环验证）

> ⚠️ **防重复调用（状态锁）**：调用前先检查 `start-state.json` 中 `completed_steps` 是否已包含当前轮次的 `3-reviewer-a-r<round>` 和 `3-reviewer-b-r<round>`。如果已存在，**跳过本步**，直接使用已有评审结论。每轮评审的 round 编号递增（第 1 轮 r1，被驳回后第 2 轮 r2，最多 r3）。
>
> **调用后置位**：每个 reviewer 返回后，执行 `python3 ${HOME}/.codebuddy/skills/beggar-workflow/beggar-state.py post-call --step "3" --agent "<reviewer或reviewer-b>" --step-id "3-reviewer-<a|b>-r<round>" --task "方案评审"`（自动递增 agent_calls_used、追加 completed_steps、追加 dispatch log）。

**⚠️ 核心规则：architect 修正后必须重新评审，直到两个 reviewer 都通过才能进入开发。**

**所有预设都使用双 reviewer 并行评审：**

Leader 必须同时发起 2 个 reviewer agent，分别从不同视角审查：

```
// reviewer-A：实现可行性视角（并行发起）→ 使用 deepseek-v4-pro
Agent({
  subagent_type: "reviewer",
  prompt: "{roles.reviewer-a}，请帮忙审一下这份方案，重点看能不能落地。\n\n完成后直接输出结果。\n\n---\n\n评审以下变更的设计方案：\n- 变更目录: openspec/changes/<change-id>/\n- 你的审查视角：【实现可行性】\n- 重点关注：代码能否写对、边界情况是否覆盖、复杂度估算是否合理、是否可测试\n- 按以下维度评估：落地可行性、可测试性、复杂度、边界情况\n- 输出评审意见\n- 必须给出明确结论：【通过】或【驳回 + 具体问题列表】",
  description: "{roles.reviewer-a} 审一下方案",
  max_turns: 40
})

// reviewer-B：技术合理性视角（并行发起）→ 使用 kimi-k2.7（跨厂商辅审）
Agent({
  subagent_type: "reviewer-b",
  prompt: "{roles.reviewer-b}，你也来审审，从不同角度看看有没有遗漏。\n\n完成后直接输出结果。\n\n---\n\n评审以下变更的设计方案：\n- 变更目录: openspec/changes/<change-id>/\n- 你的审查视角：【技术合理性】\n- 重点关注：需求是否完整、逻辑是否自洽、安全性是否有保障、是否有遗漏场景\n- 按以下维度评估：需求完整性、技术合理性、安全性、稳定性\n- 输出评审意见\n- 必须给出明确结论：【通过】或【驳回 + 具体问题列表】",
  description: "{roles.reviewer-b} 也审一下方案",
  max_turns: 40
})
```

**各预设的 reviewer 模型配置：**

| 预设 | reviewer-A（实现视角） | reviewer-B（技术视角） |
|------|----------------------|---------------------|
| economic | hy3 (x0.00) | hy3 (x0.00) |
| balanced | deepseek-v4-pro (x0.16) | kimi-k2.7 (x0.57) |
| quality | kimi-k2.7 (x0.57) | deepseek-v4-pro (x0.16) |
```

**双 reviewer 通过规则：**
- 两者都通过 → 进入 Step 4
- 任一驳回 → 合并两者意见，退回 architect 修正
- 两者意见冲突 → Leader 仲裁（取更严格的那个）

**评审闭环流程（不论单/双 reviewer，最多 3 轮）：**

1. **第 1 轮**：architect 提交方案 → reviewer(s) 评审
   - 通过 → 进入 Phase 3（Step 4 代码开发）
   - 驳回 → 退回 architect 修正，进入第 2 轮
2. **第 2 轮**：architect 修正方案（基于 reviewer 具体意见）→ reviewer(s) 重新评审（⚠️ 不可跳过此步）
   - 通过 → 进入 Phase 3
   - 驳回 → 退回 architect 再次修正，进入第 3 轮
3. **第 3 轮**：architect 再次修正 → reviewer(s) 三审
   - 通过 → 进入 Phase 3
   - 驳回 → 暂停，向用户报告分歧点

**通知规则：**
- **通过时（N7-markdown）**：如 notify 启用，执行：
  ```bash
  PROJECT=$(basename "$PWD")
  MSG="### [beggar] ✅ Phase 2 评审通过\n\n> **项目**：\`$PROJECT\`\n> **详情**：设计方案评审通过，进入开发阶段\n\n请回到对话查看"
  beggar notify "$MSG" || true
  ```
- **第 3 次驳回时（N1-voice）**：如 notify 启用，执行：
  ```bash
  PROJECT=$(basename "$PWD")
  MSG="### [beggar] ⚠️ Phase 2 第3次驳回\n\n> **项目**：\`$PROJECT\`\n> **详情**：Phase 2 第3次被驳回，需用户裁决\n\n请回到对话查看"
  beggar notify "$MSG" || true
  ```

**⚠️ 关键约束：architect 修正后绝不能直接进入开发，必须经 reviewer 重新确认通过。**

这与代码开发阶段的 Review Gate 逻辑一致——任何修改都需要重新审查才能流转到下一阶段。

### Step 4: 代码开发（分级 coder 分派）

**前置**：调用 `superpowers:subagent-driven-development` 获取 per-task 编排模式。

按 tasks.md 逐任务执行。**每个任务必须严格走完 coder → tester → reviewer 三步，不可跳过任何一步。**

**Per Task Loop（强制完整执行）:**

#### 4.1 分派 coder（使用 Agent 工具）

> ⚠️ **防重复调用（状态锁）**：调用前先检查 `start-state.json` 中 `completed_steps` 是否已包含 `4.1-coder-<level>-task<N>`。如果已存在，**跳过本步**，直接使用已有代码产物。Review Gate 升级时，新的级别标识不同（如 `4.1-coder-standard-task1`），不触发跳过。
>
> **调用后置位**：Agent 返回后，执行 `python3 ${HOME}/.codebuddy/skills/beggar-workflow/beggar-state.py post-call --step "4.1" --agent "coder-<level>" --step-id "4.1-coder-<level>-task<N>" --task "代码实现 Task<N>"`（自动递增 agent_calls_used、追加 completed_steps、追加 dispatch log）。

Leader 判断复杂度后，**必须使用 Agent 工具** spawn 对应 coder：

> ⚠️ **max_turns 按级别调整**：以下模板默认 `max_turns: 35`（coder-lite 级别），实际分派时按下表替换：
> | coder 级别 | max_turns |
> |-----------|-----------|
> | coder-lite | 35 |
> | coder-standard | 50 |
> | coder-senior | 70 |

```
Agent({
  subagent_type: "coder-<level>",
  prompt: "{roles.coder-<level>}，{greeting}让你去把这事办了。\n\n---\n\n## 任务描述\n<明确的任务描述>\n\n## 任务标签\n<标签列表>\n\n## 相关文件\n- <file_path:line>\n\n## 参照代码\n- <file_path:line — 类似实现位置>\n\n## 设计要求\n<从 design.md 摘取>\n\n## 代码规范\n读取 .codebuddy/rules/ 下对应语言的规范文件，严格遵循。不要尝试搜索确认路径存在性，直接读取。如果项目路径不存在再到 $HOME/.codebuddy/rules/ 下查找。\n\n完成后输出实现报告。",
  description: "{roles.coder-<level>} 去实现批量删除",
  max_turns: <按级别替换: coder-lite=35 / coder-standard=50 / coder-senior=70>
})
```

#### 4.2 tester 验证（不可跳过 ⚠️）

> ⚠️ **防重复调用（状态锁）**：调用前先检查 `start-state.json` 中 `completed_steps` 是否已包含 `4.2-tester-task<N>`。如果已存在，**跳过本步**，直接使用已有测试结果。coder 自修复重试时使用后缀区分（如 `4.2-tester-task1-retry1`）。
>
> **调用后置位**：Agent 返回后，执行 `python3 ${HOME}/.codebuddy/skills/beggar-workflow/beggar-state.py post-call --step "4.2" --agent "tester" --step-id "4.2-tester-task<N>" --task "测试验证 Task<N>"`（自动递增 agent_calls_used、追加 completed_steps、追加 dispatch log）。

**coder 返回结果后，Leader 必须立即调用 tester agent 验证。**

```
Agent({
  subagent_type: "tester",
  prompt: "{roles.tester}，去试试刚才写的代码能不能跑通。\n\n完成后直接输出结果。\n\n---\n\n验证刚完成的代码修改：\n\n## 修改文件\n<从 coder 报告中提取>\n\n## 验证要求\n1. 编译是否通过\n2. 相关测试是否通过\n3. 如有新功能，是否有对应测试覆盖\n\n跑完给个结果，别漏了什么。",
  description: "{roles.tester} 跑一遍测试",
  max_turns: 40
})
```

**tester 结果处理：**
- ✅ 通过 → 进入 4.3 reviewer 审查
- ❌ 失败 → coder 自修复（同级重试最多 2 次），超过则升级

#### 4.3 reviewer 审查（不可跳过 ⚠️）

> ⚠️ **防重复调用（状态锁）**：调用前先检查 `start-state.json` 中 `completed_steps` 是否已包含 `4.3-reviewer-task<N>`。如果已存在，**跳过本步**，直接使用已有审查结论。Review Gate 升级时使用后缀区分（如 `4.3-reviewer-task1-gate2`）。
>
> **调用后置位**：Agent 返回后，执行 `python3 ${HOME}/.codebuddy/skills/beggar-workflow/beggar-state.py post-call --step "4.3" --agent "reviewer" --step-id "4.3-reviewer-task<N>" --task "代码审查 Task<N>"`（自动递增 agent_calls_used、追加 completed_steps、追加 dispatch log）。

**tester 通过后，Leader 必须立即调用 reviewer agent 审查。**

```
Agent({
  subagent_type: "reviewer",
  prompt: "{roles.reviewer-a}，代码写完了，请过目。\n\n完成后直接输出结果。\n\n---\n\n审查 Task N 的代码实现：\n\n## 修改文件\n<从 coder 报告中提取>\n\n## 设计规格\n<从 design.md 摘取对应部分>\n\n## 审查要求\n1. 代码是否符合 design.md 设计要求\n2. 错误处理是否完备\n3. 命名和代码风格是否符合项目规范\n4. 是否引入潜在 bug 或安全问题\n5. 是否有遗漏的边界情况\n\n给个明确结论：【通过】或【不通过 + 具体问题列表】",
  description: "{roles.reviewer-a} 审一下代码",
  max_turns: 40
})
```

**reviewer 结果处理：**
- ✅ 通过 → 任务完成，标记 tasks.md 对应条目
- ❌ 不通过 → 触发 Review Gate 升级（见下方升级机制）

#### 4.4 Review Gate 升级处理

不通过时，Leader 必须：
1. 记录本轮失败信息
2. 升级到更高级 coder（lite→standard→senior）
3. 重新走 4.1→4.2→4.3 完整流程
4. 升级后的 coder prompt 中必须包含前一轮 reviewer 的具体意见

**独立任务并行**：当 3+ 个任务互相独立时，可并行发起多个 Agent 调用。但每个任务内部的 coder→tester→reviewer 链路仍必须串行。

> ⚠️ **委派日志**：每个 task 的 coder/tester/reviewer 调用完成后，执行 `python3 ${HOME}/.codebuddy/skills/beggar-workflow/beggar-state.py post-call --step "4.x" --agent "<agent_type>" --task "<简述>"`（自动追加 agent_dispatch.log 并递增 agent_calls_used）。**所有 Agent 调用**（不限于此处）均需追加记录。这用于委派门禁检查（见 SKILL.md 规则 7）。

**通知(N8-markdown)**: 如 notify 启用, PROJECT=$(basename "$PWD"); MSG="### [beggar] ✅ Phase 3 代码开发完成\n\n> **项目**：\`$PROJECT\`\n> **详情**：{total}个任务全部通过\n\n请回到对话查看"; beggar notify "$MSG" || true

### Step 5: 最终审查（reviewer agent）

> ⚠️ **防重复调用（状态锁）**：调用前先检查 `start-state.json` 中 `completed_steps` 是否已包含 `5-reviewer`。如果已存在，**跳过本步**，直接使用已有最终审查结论。最终审查不通过退回修复后，重新审查使用后缀区分（如 `5-reviewer-r2`）。
>
> **调用后置位**：Agent 返回后，执行 `python3 ${HOME}/.codebuddy/skills/beggar-workflow/beggar-state.py post-call --step "5" --agent "reviewer" --step-id "5-reviewer" --task "最终审查"`（自动递增 agent_calls_used、追加 completed_steps、追加 dispatch log）。

**⚡ 全部 tasks 完成后，必须做最终全量审查。不可跳过。**

**前置**：调用 `superpowers:verification-before-completion` 确保验证已执行。

```
Agent({
  subagent_type: "reviewer",
  prompt: "{roles.reviewer-a}，全部改完了，最后再过一遍。\n\n完成后直接输出结果。\n\n---\n\n对本次完整变更做最终审查：\n\n## 审查范围\n- 查看全量 git diff（使用 Bash 执行 git diff）\n- 检查跨任务一致性\n- 检查代码规范合规（读取 .codebuddy/rules/ 对应规范）\n- 验证无遗留 TODO/FIXME\n- 检查是否有冲突或重复代码\n\n## 必须输出\n- 审查结论：【通过 / 不通过】\n- 如不通过：列出具体问题和建议修复方案",
  description: "{roles.reviewer-a} 最终再过一遍",
  max_turns: 40
})
```

**最终审查不通过** → 根据问题分派对应 coder 修复 → 修复后再次调用 tester + reviewer（最多 2 轮，超过则暂停向用户报告阻塞点）
**最终审查通过** → 进入 Step 6

### Step 6: 归档与 Coder Guard 更新（recorder agent）

> ⚠️ **防重复调用（状态锁）**：调用前先检查 `start-state.json` 中 `completed_steps` 是否已包含 `6-recorder`。如果已存在，**跳过本步**，直接使用已有归档结果。
>
> **调用后置位**：Agent 返回后，执行 `python3 ${HOME}/.codebuddy/skills/beggar-workflow/beggar-state.py post-call --step "6" --agent "recorder" --step-id "6-recorder" --task "归档沉淀"`（自动递增 agent_calls_used、追加 completed_steps、追加 dispatch log）。

**前置**：调用 `superpowers:finishing-a-development-branch` 决定分支集成策略（merge/PR/keep）。

```
Agent({
  subagent_type: "recorder",
  prompt: "{roles.recorder}，活干完了，记一下档。\n\n完成后直接输出结果。\n\n---\n\n归档本次变更：\n\n1. 执行 openspec archive <change-id> -y\n2. 提取本次开发的关键经验和决策\n3. 更新 memory/coder-guard.json（如有 review 升级/失败记录）\n4. 记录格式参照 agent 配置中的规范",
  description: "{roles.recorder} 记下档",
  max_turns: 30
})
**通知(N10-markdown)**: 如 notify 启用, PROJECT=$(basename "$PWD"); MSG="### [beggar] ✅ 全流程完成\n\n> **项目**：\`$PROJECT\`\n> **详情**：{done}/{total}任务通过，已归档\n\n请回到对话查看"; beggar notify "$MSG" || true

**Coder Guard 记录格式**：
```json
{
  "history": [
    {
      "timestamp": "2026-06-02T12:00:00Z",
      "coder": "coder-lite",
      "tags": ["api_endpoint", "cross_module"],
      "result": "review_rejected",
      "escalated_to": "coder-standard"
    }
  ],
  "summary": {
    "coder-lite": {
      "api_endpoint": {"total": 5, "success": 2, "failure": 3}
    }
  }
}
```
