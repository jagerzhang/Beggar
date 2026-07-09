---
name: BEGGAR: Start
description: "启动多 Agent 研发工作流。按 设计→评审→开发→测试→审查→归档 阶段编排不同 agent 完成开发任务"
argument-hint: "<需求描述>"
---

启动 Multi-Agent 研发工作流。

**触发**：用户输入 `/beggar:start <需求描述>`，例如：
- `/beggar:start 给用户管理页面增加批量删除功能`
- `/beggar:start 修复登录后跳转空白页的 bug`

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

2. **传递需求**
   将 `$ARGUMENTS` 中的需求描述作为输入传给 beggar-workflow。

3. **遵循阶段门禁**
   - Phase 1（设计）→ 调用 `architect` agent
   - Phase 2（评审）→ 调用双 `reviewer` agent 并行（实现可行性 + 技术合理性）
   - Phase 3（开发）→ 调用 `coder` + `reviewer` + `tester` 循环
   - Phase 4（最终审查）→ 调用 `reviewer` agent
   - Phase 5（归档）→ 调用 `recorder` agent

4. **状态防护（防 context 稀释脱轨）**
   需求确认完成、openspec change 创建后，立即写入 `start-state.json`：
   ```json
   {
     "current_step": "pipeline-running",
     "change_id": "<change-id>",
     "created_at": "<ISO8601>",
     "completed_steps": [],
     "agent_calls_used": 0,
     "max_agent_calls": 60,
     "updated_at": "<ISO8601>"
   }
   ```
   路径：`openspec/changes/<change-id>/start-state.json`

   **防重复调用**：Leader 调用任何 Agent 前，必须先检查 `completed_steps` 数组是否包含该步骤标识。如果已存在，跳过调用，直接使用已有产物。调用完成后，将步骤标识追加到 `completed_steps` 并写回文件。步骤标识命名规则详见 `phases.md` 的「防重复调用机制」章节。

5. **遵循阶段产物要求**
   每个阶段必须有产物才能进入下一阶段，不允许跳过。

6. **使用当前模型预设**
   不切换预设；如需调整可先 `beggar agent preset <name>`（项目安装时也可用 `.codebuddy/setup.sh agent preset <name>`）。

---

**注意**：
- 需求模糊时，先调用 `superpowers:brainstorming` 探索
- 简单 hotfix（一行级修改、文档修改、配置修改）可直接执行，不需走流程
- 用户明确说"不走流程/直接改"时，跳过本流程
