---
name: beggar-install
description: Install or upgrade Beggar (CodeBuddy multi-agent model differentiation & cost-saving kit) via interactive conversation. Triggered when user says "install beggar", "beggar setup", "配置 beggar", "初始化 beggar", or similar.
agent_created: true
---

# Beggar Install Skill

This skill installs or upgrades Beggar — the CodeBuddy multi-agent model differentiation & cost-saving kit — through an interactive conversation-guided process.

## When to Use

Use this skill when the user wants to:
- Install Beggar for the first time
- Upgrade an existing Beggar installation
- Reconfigure Beggar settings (preset, personas, notify)
- Migrate from curl-based install to skill-based management

## Installation Flow

### Step 1: Detect Current State

Check if Beggar is already installed in the target project:

```bash
bash scripts/install.py --detect --project-dir "<target-dir>"
```

The script returns JSON:
- `installed: false` → fresh install
- `installed: true, version: "x.y.z"` → upgrade or reconfigure

### Step 2: Determine Target Directory

If the user has not specified a project directory, ask:

> 要在哪个项目目录安装 Beggar？（留空使用当前目录）

Default to the current working directory if the user leaves it blank.

### Step 3: Detect Platform (CLI vs IDE)

Run platform detection automatically:

```bash
bash scripts/install.py --detect-platform
```

The script checks:
- Presence of `codebuddy` CLI command → CLI mode
- Presence of IDE-specific env vars (e.g., `CODEBUDDY_IDE_VERSION`) → IDE mode
- Fallback: ask the user explicitly

### Step 4: Download Latest Version

```bash
bash scripts/install.py --download --project-dir "<target-dir>"
```

The script downloads the latest release from the configured mirror and extracts it into `.codebuddy/`.

### Step 5: Apply Platform-Specific Fixes

- Add a `.codebuddy/.beggar-platform` marker file containing the detected platform (`cli` or `ide`)

> **Note**: The hy3 model ID is unified across CLI and IDE. No platform-specific model ID replacement is needed.

### Step 6: Run Setup (Interactive via Conversation)

Instead of running `setup.sh` directly (which uses `read` and may fail in non-TTY environments), guide the user through configuration step by step:

1. **Choose preset** (balanced / economic / quality):
   > 请选择预设方案：
   > 1. balanced（推荐）— 平衡成本与质量
   > 2. economic — 极致省钱
   > 3. quality — 最高质量

2. **Configure notify** (optional):
   > 是否配置企业微信通知？（y/n，默认 n）
   > 如需配置，请提供 webhook URL 和接收人账号。

3. **Choose persona theme** (optional):
   > 请选择角色主题：
   > 1. beggar-gang（丐帮）
   > 2. sanguo（三国）
   > 3. shuihu（水浒）
   > 4. default（默认，无角色）

4. **Confirm model switch** (if needed):
   > 当前 Leader 模型为 `<current>`，balanced 预设推荐 `<recommended>`。
   > 是否自动切换？（y/n，默认 y）

Apply each choice by calling the appropriate `setup.sh` subcommand or editing config files directly.

### Step 7: Verify Installation

```bash
bash scripts/install.py --verify --project-dir "<target-dir>"
```

The script checks:
- All 8 agent `.md` files exist
- `subagent_type` mappings are correct
- `models.json` is valid JSON
- `persona-active.json` exists
- `.beggar-platform` marker is set

Display a summary table to the user.

### Step 8: Post-Install Guidance

Show the user how to use Beggar:

```
Beggar 安装完成！

常用命令：
  .codebuddy/setup.sh show              # 查看当前配置
  .codebuddy/setup.sh agent preset <n>  # 切换预设
  .codebuddy/setup.sh persona <theme>   # 切换角色主题
  .codebuddy/setup.sh update            # 升级 beggar

开始开发：
  在 CodeBuddy 对话中输入 /beggar:start 启动研发工作流
```

## Upgrade Flow

If Beggar is already installed:

1. Show current version and latest version
2. Ask if the user wants to upgrade
3. Backup user custom files (same as `install.sh` incremental sync)
4. Download and extract new version
5. Re-apply platform-specific fixes
6. Re-apply user customizations (persona, notify, user-models.json)
7. Verify

## Scripts Reference

| Script | Purpose |
|--------|---------|
| `scripts/install.py` | Main installation logic (detect, download, configure, verify) |

## Notes

- The skill handles IDE/CLI platform differences automatically.
- Non-TTY `read` issues are avoided by using conversation-based interaction.
- User custom files are always preserved during upgrades.
