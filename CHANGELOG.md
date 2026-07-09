# Changelog

All notable changes to the Beggar project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

---

## [v2.8.6] - 2026-07-09

### Added

- feat(workflow): 新增 `beggar-state.py` 状态管理脚本 — 封装 10 个子命令（init/set/get/post-call/check/reset/step/achieve/dispatch/find），将 Leader 固定动作（状态读写、调用后置位、安全边界检查、迭代重置等）从手动 bash 代码块替换为单行脚本调用，每次调用节省约 1750 tokens（!65）
- feat(workflow): 代码修改自动检测 — 用户未通过 `/beggar:start` 或 `/beggar:goal` 启动但需求涉及代码修改时，Leader 先询问用户选择执行方式（启用工作流 / 直接开发），避免误判角色导致暂停（!63）
- feat(test): 新增 28 个 `beggar-state.py` 单元测试，全部通过（!65）

### Fixed

- fix(workflow): 全量评审修复 7 项问题（!61）— `human_reject_limit` 默认值统一为 3；router.md 与规则6矛盾修复（Leader 直接 Read 源代码改为委派 reviewer-b）；Phase 4 最终审查无收敛上限添加最多 2 轮限制；Goal Loop 状态文件引用从 `start-state.json` 修正为 `goal-state.json`；Step 6.4 差距分析条件执行（全部 PASS 时跳过）；Step 6.6.1/6.6.2 编号倒序修正；`completed_steps` 命名规则统一
- fix(workflow): 移除对抗暂停 workaround — 根因为未通过 `beggar start` 启动导致 Agent 未加载 workflow 上下文，移除 3 处对抗性指令（phases.md Phase 2→3 衔接、Phase 3 强制衔接、SKILL.md 委派门禁）（!62）
- fix(workflow): `beggar-state.py` 评审修复 10 项（!66）— P0: `init --step` 参数化（非硬编码）、`human_reject_limit` 回归修复为 3；P1: `cmd_set` JSON 值解析、`init --no-progress-limit` 参数、Step 6.6.1/6.6.2 post-call step 值交叉修正、9 处命令路径统一为完整 `python3 ${HOME}/...` 路径、phases.md 7 处手动后置位替换为脚本命令；P2: `update.sh` 安装后自动同步脚本副本、reset 指令重复段落精简、`cmd_reset` 冗余字段合并
- fix(display): `beggar show` agent 列表遗漏 director — `display.py` 的 `agents_order` 硬编码 8 个 agent 未包含 director，追加 director 条目修复（!68）

### Changed

- change(workflow): 消除 workflow 文档上下文冗余 8 项（!64）— SKILL.md 禁写代码规则合并（~2000 tokens）、ToolSearch 警告统一（~600 tokens）、防重复调用 boilerplate 精简（~750 tokens）、max_turns 超限恢复统一引用（~500 tokens）、Director 调用提取共享模板（~800 tokens）、Director 状态锁精简为引用（~300 tokens）、费用/RTK/预设迁移到 reference.md（~500 tokens），累计节省约 5450 tokens
- change(workflow): `update.sh` 新增 `beggar-state.py` 安装后同步机制 — `do_update` 和 `do_reinstall` 均自动从 `lib/` 复制到 `skills/beggar-workflow/`，保持双副本一致（!66）

---

## [v2.8.5] - 2026-07-07

### Fixed

- fix(agents): coder/reviewer 规范文件路径读取优化 — 保持相对路径 `.codebuddy/rules/` 优先（兼容项目级和全局安装），在 agent 定义和 Leader prompt 中加入"不要搜索确认路径存在性，直接用 Read 读取"的指令，避免 LLM 优先尝试全局路径 `$HOME/.codebuddy/rules/` 或用 Grep/Search 探索路径导致浪费 3-4 turn；读取失败时再 fallback 到 `$HOME/.codebuddy/rules/`
- fix(workflow): phases.md coder prompt 模板新增 `## 代码规范` 指令段，与 reviewer prompt 的规范读取指令对齐
- fix(workflow): beggar-start 流程全 Agent 防重复调用 — 新增 `completed_steps` 状态锁，7 个 Agent 调用点全部加调用前检查 + 调用后置位，防止 context 稀释后重复 spawn

### Changed

- change(workflow): `start-state.json` 结构扩展 — 新增 `completed_steps`/`agent_calls_used`/`max_agent_calls`/`updated_at` 字段，从粗粒度 `current_step` 升级为细粒度步骤追踪
- change(workflow): 全 Agent `max_turns` 上调 — architect 40→80、coder-senior 35→70、coder-standard 25→50、coder-lite 15→35、reviewer/tester 20→40、recorder 15→30、director 10→15、goal-evaluator 5→8，解决启动探索阶段就耗尽预算导致 agent 无法完成实际工作的问题

### Added

- feat(model): 新增 `kimi-k2.7` 模型 — K2.6 编程专用强化版（Code Bench v2 +21.8%、Program-Bench +11%、MLS Bench Lite +31.5%、Agent能力+10%、长程任务token-30%），x0.65 倍率，有效成本 x0.455 低于 K2.6 的 x0.50
- feat(model): `beggar-models.json` 新增 K2.7 模型定义、aliases 映射，balanced/quality 预设 reviewer-b/tester/reviewer 角色升级到 K2.7

### Changed

- change(model): balanced 预设 reviewer-b/tester 从 `kimi-k2.6` (x0.50) 升级到 `kimi-k2.7` (x0.65)，quality 预设 reviewer 同步升级
- change(model): agent 定义 `reviewer-b.md`/`tester.md` 模型从 K2.6 更新到 K2.7
- change(model): MODEL_SELECTION.md / README / README_CN / SKILL.md / phases.md / beggar-leader-no-code.mdc 全部同步更新 K2.7 benchmark 数据和选型依据

---

## [v2.8.4] - 2026-07-06

### Added

- feat(goal): 独立验证 Agent（goal-evaluator）— Phase 6 新增独立 agent 做 yes/no 判定，取代 Leader 自判，使用与 Leader 不同的模型避免同模型自判
- feat(goal): 快速启动模式（`--fast`）— 跳过澄清和配置向导，使用标准 Profile 默认值直接进入 pipeline
- feat(goal): 条件内嵌限制 — 用户在目标描述中写"最多 5 轮"等限制语时自动提取为 `stop_after_turns` / `stop_after_minutes`
- feat(goal): 连续人工驳回 Director 介入（Step 6.6.2）— 连续 3 次人工驳回强制调用 Director 做根因分析；用户也可回复关键词手动触发
- feat(cli): `beggar reinstall` 命令 — 跳过版本检查强制重装，保留用户自定义内容

### Changed

- change(model): hy3 模型 ID 统一为 `hy3`，CLI 和 IDE 统一，旧 ID 自动迁移

### Fixed

- fix(model): hy3 → hy3 正式版更新 — 同步模型 ID、benchmark 数据（SWE-bench 78%、GPQA 90.4%、ClawEval 68.5）、文档描述和显示名
- fix(goal): Director 重复调用 + token 失控 — 移除 Agent 工具权限，max_turns 统一为 10，强化状态锁检查
- fix(goal): Director 模型漂移 — 移除调用时硬编码的 model 参数，改由 frontmatter 决定
- fix(goal): 全 Agent 防重复调用（completed_steps）— 所有 Agent 调用前检查步骤标识，避免 context 稀释后重复 spawn
- fix(workflow): 续作唤起强制前置产物检查 — max_turns 超限恢复时必须先 ls/Read 确认已产出文件
- fix(review): MR !38 审查问题修复 — JSON 缩进、ASCII 表格对齐、economic 预设 goal-evaluator 模型独立性

### Deferred

- fix(goal): Goal Loop 提示词瘦身 — 详细 prompt 模板移至按需读取文件（后续版本实施）

---

## [v2.8.3] - 2026-07-06

### Added

- feat(goal): Goal Loop 工程模式 — `/beggar:goal <目标>` 启动目标驱动宏循环，新增 Phase 0（目标定义）和 Phase 6（目标验证），支持 `resume` 跨 context 恢复
- feat(goal): Director 终审机制 + 配置向导 — 3 个预设 Profile（标准/严格/轻量）+ 自定义入口，严格模式启用 Director 终审

### Fixed

- fix(config): `models.json` → `beggar-models.json` 重命名 — 避免与 CodeBuddy 官方同名配置冲突，旧版自动迁移
- fix(goal): Director 重复调用 + 模型漂移 — 新增 3 个状态锁字段，Director 调用显式指定 model 参数
- fix(workflow): max_turns 全量调大 + 超限恢复机制 — architect 40、coder-senior 35、reviewer/tester 20 等，新增四步恢复流程
- fix(persona): 角色化调度示例跨主题污染 — 硬编码丐帮角色名替换为通用变量
- fix(goal): 多轮交互后脱离 Goal 流程 — 新增 `current_step` 状态锚定，每次交互先读锚确认步骤
- fix(persona): Step 0 硬门禁防止编造角色名 — 必须先读取 persona-active.json 才能输出角色名
- fix(workflow): Leader 多轮交互后退化为主力 — 新增委派门禁检查 + agent_dispatch.log 追踪机制
- fix(build): bsdtar 打包含 SCHILY.fflags 扩展头 — macOS bsdtar 追加 `--no-fflags` 参数
- fix(review): MR !36 审查问题修复 — Bash 工具补充、grep 匹配放宽、差距分析改委派 reviewer
- change(i18n): 全局中文输出强化 — SKILL.md 规则 8 + agent 语言指令升级为 MUST + 移除 CODEBUDDY.md 依赖

---

## [v2.8.2] - 2026-06-30

### Added

- feat(workflow): Agent 工具与 Workflow 工具区分说明 — 明确 Agent 是内建工具直接调用，不要混淆 Workflow

---

## [v2.8.1] - 2026-06-29

### Added

- feat(shell): `beggar` 命令 PATH fallback — 安装后自动注入 shell 函数，不依赖新终端窗口
- feat(persona): 技术传奇主题角色语气升级 — motto 改为口头禅式短句

### Fixed

- fix(uninstall): 卸载清单补全 — init.sh 创建的 persona-active.json、settings.json 补充记录到清单
- fix(models.sh): `beggar agent show` 兜底 — case 分支补充 `show` 别名

### Changed

- change(agents): 文件拆分定性原则替代硬数字行数限制 — "800 行上限"改为"是否按逻辑拆分"

---

## [v2.8.0] - 2026-06-26

### Added

- feat(lint): 新增 `scripts/lint.sh` shellcheck 静态分析脚本
- feat(test): 新增 66 个 Python 单元测试 + Shell Bats 测试
- feat(schema): 新增 JSON Schema 定义，validate.sh 集成校验
- feat(summary): 新增 `run_summary.py` 流水线执行摘要生成器
- feat(guard): 新增 `guard.sh` Coder Guard 导出/导入/查看命令
- feat(windows): Windows Git Bash / MSYS2 完整适配 — PYTHON_CMD 检测、ANSI 降级、路径转换、跨平台 sed
- feat(git): 新增 `.gitattributes` 强制 LF 行尾
- feat(rtk): Windows 环境自动下载预编译二进制
- feat(director): 新增隐藏升级 Agent — 3 轮全败时激活，6 类裁决分型

### Fixed

- fix(models.sh): `_check_leader_model` 未定义变量导致全局 init 后主模型被重置
- fix(preset.sh): `python3 | while read` 管道在 `set -e` 下静默吞错
- fix(install.sh): trap 单引号导致 `$tmp_dir` 延迟展开，`set -u` 下报错
- fix: 多项 Windows 兼容性修复（readlink、颜色码、进程替换、路径检测）

### Changed

- refactor(model_resolver): inline Python heredoc 提取为独立模块
- refactor(skills): SKILL.md 从 984 行拆为 3 文件（SKILL.md + router.md + phases.md），Leader 加载 token 节省约 75%
- change(phases.md): ASCII 流程图替换为 Markdown 表格/列表，富文本渲染器兼容
- change(README): ASCII 架构图替换为 SVG
- change(shell.sh): 默认推荐从 dontAsk 改为 acceptEdits（后改为 auto）

---

## [v2.7.7] - 2026-06-25

### Added

- feat(persona): 新增「技术传奇」角色主题并设为默认
- feat(agents): coder/reviewer 增加健壮性与异常处理专项要求

### Fixed

- fix: 硬编码 /root/ 路径及项目相对路径的全局兼容问题
- fix(init): 重复 init 导致 settings.json model 字段丢失

---

## [v2.7.6] - 2026-06-24

### Added

- feat: Shell 别名同步覆盖 `codebuddy` 和 `cbc` 两个命令
- feat: Shell 别名新增「全程 auto」预设模式

### Fixed

- fix(update): `set -e` 导致版本比较静默中断
- fix(agents): 移除 agent `tools:` 白名单，兼容 MCP 工具
- fix(shell): 已有 alias 但内容不同时覆盖而非跳过

### Changed

- change(shell): 默认推荐从 dontAsk 改为 acceptEdits

---

## [v2.7.5] - 2026-06-24

### Added

- feat: `beggar setup shell` 命令 — 独立的 cbc CLI 启动别名配置，支持交互式引导
- feat: quickstart 向导新增 Shell 别名步骤

---

## [v2.7.4] - 2026-06-24

### Added

- feat: 新增 GLM-5.2 (x1.06) 和 GLM-5v-Turbo (x0.81) 模型
- feat: Balanced architect 升级为 GLM-5.2，Economic architect 升级为 V4-Pro

### Fixed

- fix: Hook 命令双重转义导致变量永不展开
- fix: 全局安装下子 agent 找不到 rules 目录
- fix: 重复安装时 hooks 未变更则跳过 settings.json 写入
- fix: `beggar update` 检测到新版本后不执行更新

### Changed

- refactor: 去掉 Balanced+ 预设，直接升级 Balanced architect
- refactor: 面板模型切换改为直接写 settings.json，不再依赖命令行

---

## [v2.7.3] - 2026-06-17

### Security

- fix: Shell 注入全面修复 — 所有 Python inline 脚本改为环境变量传参

### Changed

- refactor: `setup.sh` 模块化拆分 — 2648 行拆为 14 个 .sh + 4 个 .py 模块
- refactor: settings.json 原子写入 — tempfile+rename 模式

### Added

- feat: `beggar quickstart` 交互式新手向导
- feat: `beggar` 智能全局命令 — 项目/全局安装均自动注册

### Fixed

- fix: `uninstall.sh` 空目录清理越界 — 改为白名单模式
- fix: 模块化拆分后部分命令函数缺失

---

## [v2.7.2] - 2026-06-16

### Fixed

- fix: 迁移旧版 hook 路径被解析为绝对根目录
- fix: 消息通知格式错乱

### Documentation

- docs: 本地 QR 码替换为在线 URL

---

## [v2.7.1] - 2026-06-15

### Added

- feat: `beggar` 全局命令 + `--project` 项目隔离模式
- feat: `beggar notify` 子命令 + Hook 自动通知

### Fixed

- fix: 多项通知和配置路径修复

### Changed

- refactor: notify 机制改为纯 Python，零依赖

---

## [v2.7.0] - 2026-06-13

### Added

- feat: 支持全局安装模式（`--global`）

---

## [v2.6.3] - 2026-06-12

### Added

- feat: 统一 CLI/IDE hy3 模型 ID 为 `hy3`

---

## [v2.6.2] - 2026-06-12

### Added

- feat(status): `/beggar:status` 实际执行诊断

### Fixed

- fix: idle_prompt 通知 + C++ 规范内容错配为 Python
- fix: 精简通知策略 + RTK hook 注入

---

## [v2.6.1] - 2026-06-12

### Fixed

- fix: 精简通知策略 + RTK hook 注入

---

## [v2.6.0] - 2026-06-12

### Changed

- feat(rtk): 删除本地 rtk 二进制，改为在线安装 + init 自动检测注入 hook

### Removed

- dist/tools/rtk-* 本地二进制
- dist/assets/wechat-group-qr.png

---

## [v2.5.28] - 2026-06-11

### Added

- feat(hooks): CodeBuddy Hook 通知（权限弹窗 / Bash / subagent stop）
- feat(release): build-release.sh 自动生成 release notes
- feat(uninstall): 清单式卸载 — install.sh 记录完整清单，精确删除

### Fixed

- fix: 通知 JSON 中文编码、Hook 消息格式、卸载残留

---

## [v2.5.27] - 2026-06-10

### Fixed

- fix(rtk): 版本检测改进

---

## [v2.5.26] - 2026-06-10

### Changed

- chore(brand): 标题更新为 Beggar · 赛博乞丐

---

## [v2.5.25] - 2026-06-10

### Fixed

- fix(rtk): 多平台支持 + 3 层安装 fallback

---

## [v2.5.19] - 2026-06-09

### Added

- feat(release): skill.zip 打包与上传
- feat(skill): Skill 安装方式，支持 IDE 自动适配
- feat(agents): coder-senior 增加 WebFetch/WebSearch 权限
- feat: 通知配置重复安装自动检测复用
- feat: 强制子 Agent 使用指定模型 — 所有调用必须指定 subagent_type

### Fixed

- fix: 多项安装、通知、模型切换、update 路径修复

### Changed

- refactor: 命令前缀统一从 `/dev:start` 改为 `/beggar:start`

---

## [v2.5.14] - 2026-06-08

### Added

- feat: 所有 agent 配置增加中文输出指令

---

## [v2.5.13] - 2026-06-08

### Fixed

- fix: SKILL.md notify.sh 路径修正 + README IDE 支持更新

---

## [v2.5.12] - 2026-06-08

### Changed

- refine: token hint prefix 说明

---

## [v2.5.11] - 2026-06-08

### Changed

- refine: taidu token hint

---

## [v2.5.10] - 2026-06-08

### Added

- feat: taidu token 获取提示

---

## [v2.5.9] - 2026-06-08

### Changed

- refactor: 通知统一为 wecom cs markdown

---

## [v2.5.8] - 2026-06-08

### Fixed

- fix: `_configure_notify` 提示被 `2>/dev/null` 隐藏

---

## [v2.5.7] - 2026-06-08

### Fixed

- fix: `_configure_notify` 在 `set -e` 下导致 init 失败

---

## [v2.5.6] - 2026-06-08

### Added

- feat: beggar-notifications 消息通知机制
- feat: CodeBuddy workspace 检测

### Fixed

- fix: 通知 API 映射、coder 成本梯度倒挂、颜色码 ANSI-C quoting 等多项修复

### Changed

- refactor: coder-guard 排除模型/基础设施错误，仅记录代码质量失败
- refactor: 移除 ship/mr-review 等废弃 skill

---

## [v2.1.9] - 2026-06-03

### Changed

- refactor(coder-guard): 排除模型/基础设施错误，仅记录代码质量失败

---

## [v2.1.8] - 2026-06-03

### Changed

- refactor: 移除 ship/mr-review/mr-address-review skills

---

## [v2.1.7] - 2026-06-03

### Fixed

- fix(uninstall): 卸载时保留已修改的 CODEBUDDY.md

---

## [v2.1.6] - 2026-06-03

### Fixed

- fix(uninstall): 记录业务 skill，延迟清单删除

---

## [v2.1.5] - 2026-06-03

### Fixed

- fix(uninstall): settings.json 清理逻辑优化

---

## [v2.1.4] - 2026-06-03

### Fixed

- fix(uninstall): 已安装 skill 和用户文件清理改进

---

## [v2.1.3] - 2026-06-03

### Fixed

- fix: skill 目录级跳过、models.json 自动删除、md5 校验

### Documentation

- docs: 使用文档链接

---

## [v2.0.0] - 2026-06-03

### Added

- Initial release of Beggar v2.
