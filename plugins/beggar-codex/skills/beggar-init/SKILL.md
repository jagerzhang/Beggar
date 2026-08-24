---
name: beggar-init
description: Codex 版 Beggar 开源初始化检查。执行 /beggar:init 或用户要求初始化时使用，检查 workflow、状态脚本、codegraph、Codex 子智能体能力以及可选 GitHub CLI 集成。
metadata:
  runtime: codex-native
---

# Beggar Init for Codex

初始化默认是只读诊断，除非用户明确要求，不安装插件、不修改平台配置、不覆盖已有文件。技能根目录优先使用项目 `.codex/skills`，否则使用全局 `${CODEX_HOME:-$HOME/.codex}/skills`。

## 检查顺序

```bash
SKILLS_ROOT=".codex/skills"
test -d "$SKILLS_ROOT" || SKILLS_ROOT="${CODEX_HOME:-$HOME/.codex}/skills"
test -f "$SKILLS_ROOT/beggar-workflow/SKILL.md"
command -v openspec || true
find "$SKILLS_ROOT" -name SKILL.md -maxdepth 3 | sort
python3 -c "import sys; p=sys.argv[1]; compile(open(p, encoding='utf-8').read(), p, 'exec'); print('state script syntax ok')" "$SKILLS_ROOT/beggar-workflow/beggar-state.py"
```

报告必须如实列出：技能数量、核心文件是否存在、状态脚本是否可解析、`openspec` CLI 是否可用、`codegraph` 是否可用、当前是否暴露 `multi_agent_v1__spawn_agent` / `multi_agent_v1__wait_agent`。不要检查或写入平台 Agent 注册表。

## Codegraph 处理

```bash
command -v codegraph || true
test -f .codegraph/codegraph.db && codegraph status || true
```

缺失时只报告“codegraph 不可用，后续回退到 rg/read”；不要未经用户同意全局安装依赖。若用户明确要求安装，先说明网络、权限和全局环境影响。

## 子智能体能力

Codex 子智能体只使用功能职责标签 Architect/Coder/Tester/Reviewer/Recorder/Director，不注入人格主题或自定义称呼；通过 `multi_agent_v1__spawn_agent` 的 `model` 和 `reasoning_effort` 参数路由，详见 `beggar-workflow/codex-runtime.md`。

## GitHub 集成

GitHub PR、Issue 和 CI 操作属于可选的平台适配能力，不是核心 workflow 的硬依赖。若
用户需要 GitHub 交付，优先使用当前 Codex 环境中已授权的 GitHub integration；否则检查
本机是否有 GitHub CLI：

```bash
command -v gh || true
gh auth status || true
```

认证失败时只报告 GitHub 登录阻断，不索要或回显 token，也不要把平台认证写入 skill、
代码、状态文件或普通日志。

## 初始化结果

输出四类信息：

1. ✅ 已就绪项目；
2. ⚠️ 缺失但可回退项目；
3. ❌ 阻断完整流程的项目；
4. 推荐下一步，例如 `/beggar:start <需求>`；OpenSpec 缺失时说明将使用 Markdown 降级路径，不把它报告为 Beggar 阻断项。

认证部分另外报告：GitHub integration 或 `gh auth status` 是否可用；如果未配置，说明
核心本地开发流程仍可运行，但 GitHub PR 操作需要用户先完成授权。

不得声称插件、Agent 注册或测试已通过，除非当前环境有实际检查证据。
