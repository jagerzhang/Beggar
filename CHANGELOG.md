# Changelog

All notable changes to the Beggar project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

---

## [v1.0.0] - 2026-07-09

### Added

- feat: Beggar GitHub 公网版首发 release
- feat: 多 Agent 模型差异化省钱方案 — Architect / Coder 三级分派 / 双 Reviewer 跨厂商并行评审 / Tester / Recorder / Director 终裁
- feat: 三档预设套餐（economic / balanced / quality），最佳适配 CodeBuddy 个人标准版
- feat: Goal Loop 工程模式 — 目标驱动宏循环，支持 `resume` 跨 context 恢复
- feat: Director 隐藏升级 Agent — 3 轮全败 + 自救耗尽激活，6 类裁决分型（A/B/C 自动恢复，D/E/F 上升用户）
- feat: `beggar-state.py` 状态管理脚本 — 10 个子命令，每次调用节省约 1750 tokens
- feat: 代码修改自动检测 — 未通过 `/beggar:start` 启动但需求涉及代码修改时先询问执行方式
- feat: `beggar` 全局命令 + `--project` 项目隔离模式
- feat: `beggar quickstart` 交互式新手向导
- feat: `beggar notify` 子命令 + Hook 自动通知
- feat: CodeBuddy Hook 通知（权限弹窗 / Bash / subagent stop）
- feat: 清单式卸载 — install.sh 记录完整清单，精确删除
- feat: Windows Git Bash / MSYS2 完整适配
- feat: Shellcheck 静态分析脚本 + 66 个 Python 单元测试 + Shell Bats 测试
- feat: JSON Schema 定义，validate.sh 集成校验
- feat: `run_summary.py` 流水线执行摘要生成器
- feat: `guard.sh` Coder Guard 导出/导入/查看命令
- feat: 角色主题系统（技术传奇 / 赛博乞丐等）
- feat: Skill 安装方式，支持 IDE 自动适配

### Changed

- change: 根据公网版实际模型列表重新设计模型套餐与定价 — 移除公网版不可用的 Claude/GPT/Gemini 系列，保留 GLM-5.2 / DeepSeek-V4 / Kimi-K2 / hy3 等可用模型
- change: README 标注默认预设最佳适配 CodeBuddy 个人标准版，其他版本需自定义配置
- change: 架构图从 SVG 转为 PNG，修复 GitHub 不展示问题

### Fixed

- fix: install.sh 改用静态重定向 URL 获取版本信息，不再依赖 GitHub API（避免 403 速率限制）
