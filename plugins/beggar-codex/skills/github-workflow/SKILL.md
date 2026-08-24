---
name: github-workflow
description: GitHub 仓库和 Pull Request 交付适配器。用户要求创建、审查、处理反馈或合并 GitHub PR 时使用。
metadata:
  runtime: codex-native
  platform: github
---

# GitHub Workflow Adapter

这是 Beggar 的可选 GitHub 平台适配器。核心风险路由、状态管理、测试证据和质量门禁由
`beggar-workflow` 负责；本技能只负责 GitHub Repository、Pull Request、Review、Checks
和合并动作。

## 工具优先级

1. 优先使用当前 Codex 环境已经授权的 GitHub integration 或 MCP。
2. 如果没有可用的 GitHub integration，使用本机 `gh` CLI。
3. 本地代码读取、分支操作、测试和构建使用 Git 原生命令与项目命令。
4. 不实现或猜测 GitHub REST API，不在仓库或日志中保存 token。

开始前检查：

```bash
command -v gh || true
gh auth status || true
git remote -v
```

认证失败时停止 GitHub 平台操作，报告认证阻断；本地代码验证仍可继续。

## Pull Request 闭环

### 创建或复用

- 先读取 Beggar 状态文件，确认 change、source branch 和 target branch。
- 先查询当前 source branch 的 opened PR，找到唯一匹配时复用。
- 没有匹配时才创建 PR。
- 找到多个候选、目标仓库不一致或状态冲突时暂停，不自动猜测。

常用 CLI 命令：

```bash
gh pr list --head <source-branch> --state open
gh pr create --base <target-branch> --head <source-branch> --title '<title>' --body-file <body-file>
gh pr view <number> --json number,state,headRefName,baseRefName,commits,statusCheckRollup
```

### 独立 Review

Reviewer 必须读取真实 diff，不信任 Coder 自述或已有测试结论：

```bash
gh pr diff <number>
gh pr checks <number>
```

审查结果使用 Beggar 规定的结构化 findings：

```text
FINDING-XXX:
  severity: blocker | major | minor
  dimension: <dimension>
  evidence: <file:line or command evidence>
  root_cause: <root cause>
  suggested_fix: <specific fix>
  verify_hint: <executable verification>
```

### 处理 Review 反馈

- 逐条读取未解决的 Review 线程。
- 区分代码问题、测试问题、需求变更和误报。
- 只有在用户需求和 design 允许的范围内修改代码。
- 修复后必须重新执行真实测试，并针对新 commit 独立复审。
- 不得仅通过回复评论宣称问题已解决。

### 合并

只有所有 task 完成、关键测试通过、没有 blocker/major findings，并且用户明确授权时，
才允许执行合并：

```bash
gh pr merge <number> --squash --delete-branch=false
```

如果用户没有授权自动合并，只报告“可以合并”以及证据，不执行合并。

## 安全边界

- 不读取、回显或提交 GitHub token。
- 不使用 `curl` 拼接 GitHub API 作为隐藏回退链路。
- 不因平台查询失败而伪造 PR、Review、Checks 或合并结果。
- 不把未合并 PR 记录为已完成变更。
