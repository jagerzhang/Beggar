## 任务复杂度判定与分派

**Leader 必须先给任务打标签，再查 Coder Guard 降级保护记录，最后分派 coder。**

### Step 1: 给任务打标签

从以下标签中选择 1-3 个最贴切的标签：

| 标签 | 典型场景 |
|------|---------|
| `config_edit` | 纯配置文件修改（`.env`、`.json`、`.yaml`、`.toml`） |
| `crud_field` | 单字段增删改查 |
| `copy_pattern` | 复制已有模式的重复代码 |
| `api_endpoint` | 新增/修改 API endpoint 及 handler |
| `ui_component` | 前端新增/修改页面、组件、样式 |
| `cross_module` | 跨模块/跨子项目联动修改 |
| `security_related` | 认证、加密、权限、token |
| `concurrency` | goroutine、channel、mutex、分布式锁 |
| `performance` | 缓存、索引、批处理、异步 |
| `database` | schema 变更、migration、复杂查询 |
| `test_only` | 仅编写/更新测试 |
| `docs_only` | 仅文档、注释、README |
| `refactor` | 不修改外部行为的内部重构 |
| `bugfix_simple` | 逻辑明确、单文件、范围局限 |
| `bugfix_complex` | 根因不清、跨文件、需深入调查 |

### Step 2: 查 Coder Guard 降级保护

**在分派前，Leader 必须读取 `memory/coder-guard.json`（不提交 git，本地持久化）。**

```
查询逻辑：
1. 根据任务标签确定 planned_coder（如 [config_edit] → coder-lite）
2. 查 guard.json 中该 coder 在这些标签上的最近 5 次记录
3. 如果失败次数 ≥ 2 次：触发降级保护，跳过 planned_coder
4. 降级后重新查询（如 lite → standard → senior）
```

**降级保护触发示例**：
```
任务标签: [api_endpoint]
计划分派: coder-lite
查 guard: coder-lite 在 api_endpoint 标签上最近 5 次有 3 次 review_rejected
结果: 触发保护，改派 coder-standard
```

### Step 3: 复杂度分级

#### coder-lite（简单任务，免费模型）

适用标签：`config_edit`、`crud_field`、`copy_pattern`、`docs_only`

适用场景：
- 纯配置修改
- 单字段增删改
- 复制已有模式的重复代码
- 修改常量、文案、样式值
- 添加已有模板的 API route
- 单行 bug 修复（逻辑明确）

#### coder-standard（中等任务，低价模型）

适用标签：`api_endpoint`、`ui_component`、`test_only`、`refactor`、`bugfix_simple`

适用场景：
- 常规业务功能实现（有 design.md 指导）
- 非架构性 bug 修复
- 新 API endpoint + 业务逻辑
- 编写/更新单元测试
- 前端新页面/组件（有参照）
- 数据库迁移脚本

#### coder-senior（复杂任务，中价模型）

适用标签：`cross_module`、`security_related`、`concurrency`、`performance`、`database`、`bugfix_complex`

适用场景：
- 架构变更或新模式引入
- 跨模块/跨子项目联动修改
- 性能优化、并发/分布式逻辑
- 安全相关（认证、加密、权限）
- 无先例的新功能
- 低级 coder 2 轮 review 未通过的升级任务

### 分派 Prompt 模板

Leader 在调用 coder agent 时，必须在 prompt 中提供：

```
使用 coder-<level> 代理实现以下任务：

## 任务描述
<明确的任务描述>

## 任务标签
<任务标签列表，如 [api_endpoint, cross_module]>
（Coder 完成后需在报告中输出这些标签）

## 相关文件
- <file_path:line — 需要修改的文件和位置>

## 参照代码
- <file_path:line — 项目中类似实现的位置，供 coder 模仿>

## 设计要求
<从 design.md 摘取的对应设计段落>

## 注意事项
<特殊约束或边界条件>
```

## Review Gate 升级机制

```
coder-lite 实现
    │
    ▼
tester 验证 ─── 编译/测试失败 → coder-lite 自修复（最多2次）→ 超过则升级
    │                                                        ↓
    ▼                                              coder-standard 接手
reviewer 审查
    │
    ├─ 通过 → 任务完成 ✓
    │
    └─ 不通过（升级轮次1）→ coder-standard 修复
                              │
                              ▼
                         reviewer 二审
                              │
                              ├─ 通过 → 任务完成 ✓
                              │
                              └─ 不通过（升级轮次2）→ coder-senior 修复
                                                        │
                                                        ▼
                                                   reviewer 三审
                                                        │
                                                        ├─ 通过 → 任务完成 ✓
                                                        │
                                                        └─ 不通过（升级轮次3）→ 进入【3轮失败应急处理】
```

**关键规则：**
- Review 不通过后，修复任务自动升级一档 coder（不退回原级）
- 编译/测试失败时，同级 coder 先尝试自修复 2 次，超过才升级
- 最多 3 轮 review（3 个不同级别的 coder 各做一次）
- **Coder Guard 记录**：每次升级触发时，recorder 必须将失败记录写入 `memory/coder-guard.json`（不提交 git），供 Leader 下次分派时查询降级保护

## 3轮失败应急处理

当 lite → standard → senior 都未能通过 review 时，Leader 必须执行以下根因分析流程（而不是直接抛给用户）：

### Step 1: Leader 根因分析

Leader 读取全部 3 轮实现报告 + reviewer 意见，判断失败根因（分类字母与 Director 裁决一致，见 Step 2.5）：

| 分类 | 根因类型 | 判断依据 | Leader 自救策略 |
|------|---------|---------|----------------|
| **A** | 设计缺陷 | 3 个 coder 都按 design.md 做，但 reviewer 指出的问题指向设计本身 | → Step 2A: architect 重新评估设计 |
| **B** | 任务过大 | 每个 coder 都实现了部分逻辑，但 reviewer 发现遗漏/不一致 | → Step 2B: 拆分为更小的子任务 |
| **C** | reviewer 误判 | 3 个 coder 的实现逻辑一致且合理，reviewer 意见自相矛盾 | → Step 2C: Leader 仲裁，更换 reviewer |
| **D** | 需求不清 | 每个 coder 理解不同，实现方向不一致 | → Step 2D: 重新澄清需求 |
| **E** | 能力天花板 | 确实是当前所有模型都无法解决的难题 | → Step 3: 用户裁决（最终兜底） |
| **F** | 环境限制 | 测试/编译失败与代码逻辑无关（环境配置、依赖缺失） | → Step 2E: 跳过环境阻塞，记录为已知问题 |

### Step 2A: 设计缺陷 → architect 重新评估

```
Leader → architect agent:
"Task X 经过 lite/standard/senior 三轮实现都未通过 review。
设计文档: <design.md 相关段落>
Reviewer 核心意见: <汇总>
请重新评估设计是否可行，是否需要调整架构或拆分任务。"
```

- architect 重新评估后，可能输出修正后的 design.md
- 修正后的设计重新进入 Phase 3（从 coder-lite 开始新一轮）
- 最多允许 **1 次设计修正**，如果修正后仍失败 → Step 3

### Step 2B: 任务过大 → 拆分任务

```
Leader 将 Task X 拆分为 Task X-1, X-2, X-3:
- X-1: 最小可工作单元（先让 lite 做最简单的部分）
- X-2: 依赖 X-1 的扩展功能
- X-3: 边界情况/错误处理

每个子任务独立走 Review Gate（各自有 3 轮机会）
```

**拆分原则**：每个子任务只涉及 1 个文件或 1 个独立逻辑单元

### Step 2C: reviewer 误判 → Leader 仲裁

```
Leader 委派 reviewer-b agent 审查（禁止 Leader 自行 Read 源代码，见 SKILL.md 规则 6）:
1. reviewer-b 读取 3 个 coder 的实现代码，对比实现逻辑一致性
2. reviewer-b 对比 reviewer 的 3 轮意见，检查是否矛盾
3. reviewer-b 参照项目中类似实现，判断 reviewer 是否误判

如果 reviewer-b 判断 reviewer 有误:
- Leader 直接接受当前实现（标记为 "Leader override"）
- recorder 记录 reviewer 误判到 coder-guard.json
- 下次同类任务更换 reviewer 模型
```
**通知(N5-voice)**: 如 notify 启用, PROJECT=$(basename "$PWD"); MSG="### [beggar] ⚠️ reviewer 疑似误判, Leader 已介入\n\n> **项目**：\`$PROJECT\`\n> **详情**：Leader 已介入仲裁\n\n请回到对话查看"; beggar notify "$MSG" || true

### Step 2D: 需求不清 → 重新澄清

```
Leader 向用户确认:
"Task X 经过 3 轮实现，coder 对以下需求理解不一致：
- 点 A: lite 理解为 X，standard 理解为 Y
- 点 B: design.md 未明确说明

请确认正确理解：
1. 选项 A: <...>
2. 选项 B: <...>
3. 其他: <用户补充>
"
```

需求澄清后，基于新理解重新分派（从 coder-lite 开始）

**⚠️ 收敛限制：需求澄清最多 1 次。** 如果第二次仍然需求不清导致 3 轮失败，
直接进入 Step 3（用户裁决），不再循环。

### Step 2E: 环境问题 → 跳过阻塞

```
如果编译/测试失败是由环境配置导致（非代码逻辑错误）：
- Leader 委派 reviewer-b agent 验证代码逻辑正确性（禁止 Leader 自行 Read 源代码，见 SKILL.md 规则 6）
- 标记为 "environment_blocker"，跳过 tester 验证
- recorder 记录环境已知问题
- 任务视为完成（后续由用户手动在正确环境中验证）
```

### Step 2.5: Director 终裁（隐藏升级）

> **设计意图**：在把问题交给用户之前，用最强模型做最后一次全局分析。Director 不参与日常流程，仅在 3 轮全败 + Leader 的 Step 2A-2E 策略全部耗尽后激活，单次调用成本约几毛钱，触发概率极低。

**激活条件**：以下任意一条满足时，Leader 召唤 Director：

- Step 2A 设计修正后再次失败 → Director 判定是否需要第二次设计修正或该放弃
- Step 2B-2E 都行不通 → Director 给出最终结论
- 根因类型为「能力天花板」→ Director 替代 Step 3 做分析（减少用户决策负担）

**调用方式**：

```
Leader → director agent:
"全部失败简报:
- 需求: <原始需求>
- 3 轮实现摘要: lite→standard→senior 各被驳回的理由
- Leader 已尝试的策略: <Step 2A-2E 中尝试过哪些>
- Leader 判断的根因: <类型>

请做最终裁决。"
```

**Director 的 6 类裁决**：

| 分类 | 判定 | Director 动作 | 流程走向 |
|------|------|-------------|---------|
| A - 设计缺陷 | architect 方案本身有问题 | 直接修改 design.md 标注缺陷 | 回到 Phase 3（1 次机会） |
| B - 任务过大 | 需求应拆分为子任务 | 输出拆分建议（N 个任务 + 描述） | Leader 拆分后重新分派 |
| C - reviewer 误判 | 某轮实现其实可接受 | 标注被误判的轮次和理由 | Leader 接受该实现，task 完成 |
| D - 需求不清 | 原始需求有歧义/矛盾 | 列出需用户澄清的具体问题 | → Step 3，附带 Director 问题 |
| E - 能力天花板 | 当前模型组合确实做不到 | 建议切 quality 预设或手动接管 | → Step 3，附带 Director 分析 |
| F - 环境限制 | 缺少依赖/权限/配置 | 列出缺失项 | → Step 3，附带清单 |

**裁决后的流程**：
- A/B/C → 流程**自动恢复**，用户不被打断。Leader 通知(N6-voice)知会进展。
- D/E/F → 进入 Step 3，但用户收到的报告已附带 Director 的分析结论（不再是一堆原始失败日志）。

**通知(N6-voice)**: 如 notify 启用, PROJECT=$(basename "$PWD"); MSG="### [beggar] 🎯 Director 介入\n\n> **项目**：\`$PROJECT\`\n> **裁决**: {分类} — {一句话结论}\n> **状态**: {自动恢复 / 需用户决策}"; beggar notify "$MSG" || true

> 当 Director 给出 D/E/F 裁决（即自动恢复策略全部耗尽，需上升用户）时，额外触发 N4 通知：

**通知(N4-voice)**: 如 notify 启用, PROJECT=$(basename "$PWD"); MSG="### [beggar] ⚠️ 自动恢复策略耗尽, 需最终裁决\n\n> **项目**：\`$PROJECT\`\n> **详情**：含 Director 在内的所有自动恢复策略已耗尽\n\n请回到对话查看"; beggar notify "$MSG" || true

### Step 3: 用户裁决（最终兜底）

当以上所有策略都无法解决问题时，向用户呈现完整上下文：

**通知(N9-voice)**: 如 notify 启用, PROJECT=$(basename "$PWD"); MSG="### [beggar] ⚠️ {count}个问题需您拍板\n\n> **项目**：\`$PROJECT\`\n> **详情**：{count}个问题需要您裁决\n\n请回到对话查看"; beggar notify "$MSG" || true

```markdown
## ⚠️ 任务阻塞 — 需要您裁决

**任务**: Task X (<描述>)
**已尝试**: lite → standard → senior + architect 重评估
**根因分析**: <Leader 判断的根因类型>

**3 轮实现概要**:
- lite: <实现思路> — 未通过原因: <...>
- standard: <实现思路> — 未通过原因: <...>
- senior: <实现思路> — 未通过原因: <...>

**可选方案**:
1. 【接受当前实现】有已知风险/限制，但可运行
2. 【手动修复】您提供具体修改方向，Leader 转述给 coder
3. 【降低验收标准】调整 reviewer 的通过标准（如跳过某些检查）
4. 【搁置任务】标记为 block，等外部条件成熟后再处理
5. 【其他】您有其他建议
```

## 任务拆分与并行执行

当一个大需求包含多个独立子任务时：

1. **Leader 分析任务依赖关系**
2. **独立任务并行分派**：给不同的 coder agent 同时执行
3. **有依赖的任务串行**：前置任务完成后再分派后续任务

```
tasks.md 中有 5 个任务：
  Task 1 (简单, 无依赖) → coder-lite
  Task 2 (中等, 无依赖) → coder-standard
  Task 3 (中等, 依赖 Task 1) → 等 Task 1 完成后 → coder-standard
  Task 4 (复杂, 无依赖) → coder-senior
  Task 5 (简单, 依赖 Task 4) → 等 Task 4 完成后 → coder-lite

并行执行: Task 1 + Task 2 + Task 4 同时开始
串行等待: Task 3 等 Task 1, Task 5 等 Task 4
```

## Goal Loop 迭代任务分派

> 当 Goal Loop 差距分析生成新 tasks 时，这些 tasks **仍然遵循标准分派流程**：打标签 → 查 Coder Guard → 分级分派。不能因为是"修复任务"就跳级或跳过降级保护检查。

### 迭代 tasks 的特殊性

| 方面 | 标准 Pipeline | Goal Loop 迭代 |
|------|-------------|---------------|
| tasks 来源 | architect 设计产出 | Leader 差距分析产出 |
| 设计依据 | design.md | 上轮验证报告 + goal.md |
| 分派流程 | ✅ 标准（标签→Guard→分派） | ✅ 标准（完全相同） |
| Coder Guard | ✅ 查询 | ✅ 查询（迭代可能触发降级） |

### 差距修复 task 的标签建议

| 差距类型 | 常见标签 | 建议起始 coder |
|---------|---------|--------------|
| 实现不完整 | `copy_pattern` / `crud_field` | coder-lite（复制已有模式） |
| 实现有误 | `bugfix_simple` / `bugfix_complex` | 按 Coder Guard 查询结果决定 |
| 验收标准遗漏 | `test_only` / `docs_only` | coder-lite |
| 设计缺陷 | 回 Phase 1，不直接生成 task | — |

> ⚠️ **注意**：如果某类差距在多轮迭代中反复出现，Coder Guard 会记录该标签的失败率，自动触发降级保护。这是预期行为，说明该类任务需要更高级 coder。

## ⚠️ 流程升级请求

```markdown
**阻塞阶段**: <Phase X>
**任务**: <Task N>
**已尝试次数**: <N>
**当前 Coder 级别**: <lite/standard/senior>
**核心问题**:
- reviewer 意见: <...>
- coder 实现: <...>

**请用户裁决**:
1. 选项 A: <...>
2. 选项 B: <...>
3. 其他方案 / 跳过此任务 / 终止流程
```
