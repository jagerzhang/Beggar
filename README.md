# Beggar — CodeBuddy Multi-Agent Model Differentiation & Cost-Saving Kit

**English** | [中文](README_CN.md) | [Model Selection Rationale](MODEL_SELECTION.md) | [Personas](PERSONAS.md) | [Changelog](../CHANGELOG.md)

Reusable multi-agent development configuration for [CodeBuddy Code](https://cnb.cool/codebuddy/codebuddy-code) (CLI & IDE).

> **Compatibility**: Fully compatible with both CodeBuddy CLI and IDE. Sub-agents use the `Agent` tool which is available in both environments. Model differentiation (`coder-lite` → hy3, `coder-standard` → V4-Flash, etc.) works in CLI via the `model` parameter; IDE uses the panel model with agent instruction differentiation.

>

## Quick Start

### Option 1: Online Script Install (recommended for CLI)

```bash
# Interactive mode — choose project or global install
curl -fsSL https://github.com/jagerzhang/beggar/raw/main/install.sh | bash

# Direct global install (to ~/.codebuddy/, shared across all projects)
curl -fsSL https://github.com/jagerzhang/beggar/raw/main/install.sh | bash -s -- --global
```

> ⚠️ **Windows users**: Do NOT run the above command directly in PowerShell / cmd.exe (PowerShell aliases `curl` to `Invoke-WebRequest`, which doesn't accept `-fsSL`). Use **Git Bash** or **WSL** instead — see the [Compatibility](#compatibility) section below.

> **Install modes**:
> - **Project install** (default): Installs to project `.codebuddy/`, config follows the project
> - **Global install** (`--global`): Installs to `~/.codebuddy/`, inherited by all projects
> - Project and global can coexist: project-level agents/rules/skills take priority, global acts as fallback

### Option 2: Skill Install (recommended for IDE)

In a CodeBuddy conversation, simply type:

> **Install beggar via https://github.com/jagerzhang/beggar/releases/latest/download/beggar-skill.zip**

The AI will automatically download, install, and guide you through configuration, auto-detecting CLI vs IDE and adapting model configurations accordingly.

### Post-Install Commands

```bash
# Update to latest version (re-run install script for incremental sync)
curl -fsSL https://github.com/jagerzhang/beggar/raw/main/install.sh | bash

# Choose a preset
.codebuddy/setup.sh agent preset balanced

# View current configuration
.codebuddy/setup.sh show
```

## What's Included

| Component | Description |
|-----------|-------------|
| `agents/` | 9 specialized sub-agents (architect, coder-senior, coder-standard, coder-lite, reviewer, reviewer-b, tester, recorder, director) |
| `beggar-models.json` | Model catalog, presets, aliases, complexity routing, review gate rules |
| `setup.sh` | One-stop setup & model configuration management |
| `rules/` | Code standards + RTK token optimization + **leader-no-code enforcement** |
| `skills/` | Dev workflow, OpenSpec change management |
| `commands/` | `/beggar:start`, `/beggar:status` slash commands |

## Agent Architecture

![Beggar Multi-Agent Architecture (balanced preset)](docs/architecture-balanced.svg)

> The diagram shows the default **balanced** preset model configuration. For `economic` / `quality` preset mappings, see the "Model Presets" section below.

**Flow essentials**:
- **Leader** (orchestration, never writes code) → **Architect** (design + gate review)
- Architect auto-dispatches to **Coder-Lite / Coder-Standard / Coder-Senior** by task complexity
- After coder finishes → **Tester** (build + test verification) → **Dual Reviewers in parallel** (primary DeepSeek + secondary Kimi, cross-vendor validation)
- Both reviewers pass → **Recorder** (knowledge capture) → task complete
- **Review Gate escalation** (red dashed): failed review → auto-upgrade to higher coder tier for rewrite
- **Director** (hidden escalation, activated on 3-round failure): 6-class verdict, A/B/C auto-recovery, D/E/F escalate to user

### Dual Reviewer Mechanism

After a coder agent completes its work, code enters **both reviewers simultaneously** for cross-validation:

| Reviewer | Perspective | Focus | Model (balanced) |
|----------|-------------|-------|------------------|
| **reviewer (primary)** | Implementation quality | Code standards, security, edge cases, spec compliance | deepseek-v4-pro |
| **reviewer-b (secondary)** | Technical soundness | Architecture design, API choices, performance impact, maintainability | kimi-k2.7 |

**Design rationale**:
- **Cross-vendor complementarity**: architect uses GLM-5.2 (Z.AI), reviewer uses DeepSeek primary + Kimi secondary, three-vendor cross-validation avoids single-model blind spots
- **Dual-angle coverage**: Implementation layer + design layer, reducing missed issues
- **Non-blocking**: Both reviewers run independently; either approval does not wait for the other

### Key Rules

- **Leader never writes code** — All code modifications go through coder agents (`beggar-leader-no-code.mdc`)
- **Complexity-based routing** — Leader analyzes task complexity and dispatches to the right coder tier
- **Review Gate escalation** — Failed review auto-upgrades to the next coder tier (max 3 rounds); 3-round failure activates director for final arbitration

## Model Presets

| Preset | Weighted Cost | Savings | Description |
|--------|---------------|---------|-------------|
| `economic` | ~x0.05 | **97%** | V4-Pro architecture + V4-Flash code + Hy3 review/testing |
| `balanced` | ~x0.29 | **91%** | GLM-5.2 architecture + V4 code + Kimi testing/review (recommended) |
| `quality` | ~x1.05 | **56%** | Opus orchestration + Sonnet/V4-Pro code + Kimi review + Flash testing |

> Savings calculated against full Claude Opus (x3.33) baseline.

### Preset Configurations

#### Economic — Maximum Savings

| Agent | Model | Cost | Rationale |
|-------|-------|------|-----------|
| Leader | kimi-k2.7 / deepseek-v4-pro | x0.65 / x0.13 | Developer's choice, V4-Pro Agent Elo 1554 higher & cheaper |
| architect | deepseek-v4-pro | x0.13 | SWE-bench 80.6%≈Opus, direction-setter can't be weaker than coder-senior |
| coder-senior | deepseek-v4-pro | x0.13 | SWE-bench 80.6%≈Opus, LiveCodeBench 93.5% highest |
| coder-standard | deepseek-v4-flash | x0.05 | SWE-bench 79%, 13-point jump over V3.2 |
| coder-lite | hy3 | x0.00 | SWE-bench 78%, strongest free model for pattern copying |
| reviewer | hy3 | x0.00 | SWE-bench 78%+GPQA 90.4%, code comprehension+reasoning |
| reviewer-b | hunyuan-2.0-thinking | x0.00 | Free+reasoning, secondary technical soundness review |
| tester | hy3 | x0.00 | WorkBuddy 90% success+ClawEval 68.5, strong agent capability |
| recorder | hy3 | x0.00 | SWE-bench 78%+reasoning, knowledge distillation |
| director | claude-opus-4.6-1m | x3.33 | Economy mode uses 4.6 (avoid 4.8 hallucinations) |

#### Balanced — Recommended for Daily Use

| Agent | Model | Cost | Rationale |
|-------|-------|------|-----------|
| Leader | kimi-k2.7 / deepseek-v4-pro / glm-5.2 | x0.65 / x0.13 / x1.06 | Developer's choice |
| architect | glm-5.2 | x1.06 | Terminal-Bench 81%>>V4-Pro 67.9%, SWE-Pro 62.1%>55.4%, reasoning depth impacts entire chain |
| coder-senior | deepseek-v4-pro | x0.13 | SWE-bench 80.6%, Agent Elo 1554>GLM-5.1(1535), 72% cheaper |
| coder-standard | deepseek-v4-flash | x0.05 | SWE-bench 79%, highest token share needs extreme value |
| coder-lite | hy3 | x0.00 | SWE-bench 78%, strongest free, escalation fallback |
| reviewer | deepseek-v4-pro | x0.13 | SWE-bench 80.6% code comprehension, GPQA 90.1% |
| reviewer-b | kimi-k2.7 | x0.65 | Cross-vendor: GLM architect / DeepSeek primary / Kimi secondary, code-optimized, token-30% |
| tester | kimi-k2.7 | x0.65 | Code-optimized, Agent +10%, token-30%, vendor diversity |
| recorder | hy3 | x0.00 | SWE-bench 78%+reasoning, low-priority stays free |
| director | claude-opus-4.7-1m | x3.33 | Default recommendation, balanced reasoning vs cost |

#### Quality — Critical Projects

| Agent | Model | Cost | Rationale |
|-------|-------|------|-----------|
| Leader | claude-opus-4.7-1m | x3.33 | Strongest reasoning, SWE-bench 87.6% for precise routing |
| architect | claude-opus-4.7-1m | x3.33 | Design is the source of truth, needs best reasoning |
| coder-senior | claude-sonnet-4.6-1m | x2.00 | SWE-bench Pro 64.3% highest, hardest tasks need Claude |
| coder-standard | deepseek-v4-pro | x0.13 | SWE-bench 80.6%>Sonnet(79.6%), 72% cheaper & stronger |
| coder-lite | deepseek-v4-flash | x0.05 | SWE-bench 79%, quality mode avoids frequent escalation |
| reviewer | kimi-k2.7 | x0.65 | Primary: cross-vendor review, Claude+DeepSeek code / Kimi third-party perspective, code-optimized |
| reviewer-b | deepseek-v4-pro | x0.13 | Secondary: SWE-bench 80.6%, supplements code depth |
| tester | gemini-3.5-flash | x0.99 | Terminal-Bench 76.2% highest, MCP Atlas 83.6%, Agent Elo 1656 |
| recorder | claude-haiku-4.5 | x0.67 | Quality mode demands high-quality knowledge capture |
| director | claude-opus-4.7-1m | x3.33 | Quality mode uses 4.7-1M, 1M window for extreme cases |

```bash
# Switch preset
.codebuddy/setup.sh agent preset economic

# Use alias (shorthand)
.codebuddy/setup.sh agent custom "kimi k2.7"
.codebuddy/setup.sh agent custom sonnet

# Inherit main panel model
.codebuddy/setup.sh agent inherit

# Show current config
.codebuddy/setup.sh show
```

## Coder Tier Routing

Leader automatically dispatches tasks based on complexity:

| Tier | Model (balanced) | Cost | Use For |
|------|------------------|------|---------|
| `coder-lite` | hy3 | x0.00 | Config changes, single-field CRUD, copy-paste patterns |
| `coder-standard` | deepseek-v4-flash | x0.05 | Regular features, bug fixes, API endpoints, tests |
| `coder-senior` | deepseek-v4-pro | x0.13 | Architecture changes, cross-module, security, concurrency |

Review fails → auto-upgrade to next tier. Max 3 rounds before director activates for root-cause analysis & final arbitration.

## Available Models

Complete model catalog for custom configuration:

### Claude Series

| Model | ID | Cost | Type | Platform | Recommended For |
|-------|----|------|------|----------|----------------|
| Claude-Opus-4.8 | claude-opus-4.8 | x3.50 | reasoning | IDE | Leader, architect |
| Claude-Opus-4.8-1M | claude-opus-4.8-1m | x3.50 | reasoning, long-context | IDE | Leader, architect |
| Claude-Opus-4.7 | claude-opus-4.7 | x3.33 | reasoning | CLI+IDE | Leader, architect |
| Claude-Opus-4.7-1M | claude-opus-4.7-1m | x3.33 | reasoning, long-context | CLI+IDE | Leader, architect, coder-senior |
| Claude-Opus-4.6 | claude-opus-4.6 | x3.33 | reasoning | CLI+IDE | Leader, architect |
| Claude-Opus-4.6-1M | claude-opus-4.6-1m | x3.33 | reasoning, long-context | CLI+IDE | Leader, architect |
| Claude-Sonnet-4.6 | claude-sonnet-4.6 | x2.00 | general | CLI | coder-senior, coder-standard |
| Claude-Sonnet-4.6-1M | claude-sonnet-4.6-1m | x2.00 | general, long-context | CLI+IDE | coder-senior, reviewer |
| Claude-Haiku-4.5 | claude-haiku-4.5 | x0.67 | fast | CLI+IDE | coder-lite, recorder |

### GPT Series

| Model | ID | Cost | Type | Platform | Recommended For |
|-------|----|------|------|----------|----------------|
| GPT-5.5 | gpt-5.5 | x3.31 | general | CLI+IDE | Leader, architect |
| GPT-5.4 | gpt-5.4 | x1.65 | general | CLI+IDE | coder-senior |
| GPT-5.3-Codex | gpt-5.3-codex | x1.25 | code | CLI+IDE | coder-senior, coder-standard |
| GPT-5.1-Codex | gpt-5.1-codex | x0.90 | code | CLI | coder-senior, coder-standard |
| GPT-5.1-Codex-Mini | gpt-5.1-codex-mini | x0.18 | code, fast | CLI | coder-lite |

### Gemini Series

| Model | ID | Cost | Type | Platform | Recommended For |
|-------|----|------|------|----------|----------------|
| Gemini-3.5-Flash | gemini-3.5-flash | x0.99 | fast | CLI+IDE | tester |
| Gemini-3.1-Pro | gemini-3.1-pro | x1.32 | general | CLI+IDE | architect, reviewer |
| Gemini-2.5-Pro | gemini-2.5-pro | x0.90 | reasoning | CLI+IDE | ⚠ CLI frequently routes to unavailable region, not recommended |

### Kimi Series

| Model | ID | Cost | Type | Platform | Recommended For |
|-------|----|------|------|----------|----------------|
| **Kimi-K2.7** 🆕 | kimi-k2.7 | x0.65 | code, agent, tool-use, long-context | CLI+IDE | Leader, reviewer, reviewer-b, tester |
| Kimi-K2.6 | kimi-k2.6 | x0.50 | agent, tool-use, long-context | CLI | Leader (legacy, upgrade recommended) |

### GLM Series

| Model | ID | Cost | Type | Platform | Recommended For |
|-------|----|------|------|----------|----------------|
| GLM-5.2 | glm-5.2 | x1.06 | code, agent, reasoning, long-context | CLI+IDE | Leader, architect, coder-senior, reviewer |
| GLM-5.1 | glm-5.1 | x0.90 | code, agent | CLI | coder-senior |
| GLM-5v-Turbo | glm-5v-turbo | x0.81 | multimodal | CLI | (multimodal scenarios) |
| GLM-5.0 | glm-5.0 | x0.68 | general | CLI | coder-standard (fallback) |
| GLM-4.7 | glm-4.7 | x0.23 | general, fast | CLI | recorder (fallback) |

### MiniMax Series

| Model | ID | Cost | Type | Platform | Recommended For |
|-------|----|------|------|----------|----------------|
| MiniMax-M2.7 | minimax-m2.7 | x0.19 | general, fast | CLI | recorder (fallback) |
| MiniMax-M2.5 | minimax-m2.5 | x0.13 | general, fast | CLI | (simplest tasks only) |

### DeepSeek Series

| Model | ID | Cost | Type | Platform | Recommended For |
|-------|----|------|------|----------|----------------|
| DeepSeek-V4-Pro | deepseek-v4-pro | x0.13 | code, agent, reasoning, long-context | CLI | coder-senior, coder-standard, reviewer, Leader |
| DeepSeek-V4-Flash | deepseek-v4-flash | x0.05 | code, fast, long-context | CLI | coder-standard, coder-lite |
| DeepSeek-V3.2 | deepseek-v3-2-volc | x0.15 | general | CLI | (legacy, upgrade to V4) |

### Free Models

| Model | ID | Cost | Type | Platform | Recommended For |
|-------|----|------|------|----------|----------------|
| Hy3 | hy3 | x0.00 | general, agent, reasoning | CLI | coder-lite, reviewer, tester, recorder |
| Kimi-K2.5 | kimi-k2.5 | x0.00 | general, agent | CLI | tester (fallback) |
| Hunyuan-2.0-Thinking | hunyuan-2.0-thinking | x0.00 | reasoning | CLI | architect (fallback) |

### Model Selection Guide

Match models to agent roles based on core capability requirements:

| Role Type | Core Need | Look For Tags | Avoid |
|-----------|-----------|---------------|-------|
| Orchestration (Leader) | Task decomposition, tool calling | agent, tool-use, long-context | Pure code models |
| Reasoning (architect, reviewer) | Deep thinking, logical validation | reasoning | fast/budget models |
| Code Generation (coder-*) | Code output, instruction following | code | Pure reasoning models |
| Execution (tester) | Command running, result parsing | agent, tool-use | Pure reasoning models |
| Summarization (recorder) | Knowledge distillation | general/reasoning | Expensive models (wasted budget) |

## CLI Model Notes

- All models use kebab-case IDs (e.g., `claude-sonnet-4.6-1m`)
- Free tier models (hy3, kimi-k2.5, hunyuan-2.0-thinking) provide significant cost savings
- `setup.sh` accepts standard IDs and shorthand aliases

## Token Optimization

Three-layer cost saving:
1. **Model tiering** — Right model for each phase (97% savings with economic preset)
2. **RTK compression** — Terminal output compressed 60-90% (installed via `setup.sh init`)
3. **Built-in tools priority** — Prefer Read/Grep/Glob built-in tools over shell commands

## Development Workflow

### Full Workflow (new features / complex changes)

```bash
# Propose → Design → Implement → Review → Test → Archive
# Leader auto-dispatches tasks to the right coder tier
/beggar:start <requirement>

# Check current workflow progress
/beggar:status
```

### Quick Fixes (hotfix / config / lint)

Even when skipping the full workflow, **Leader never writes code directly**. All code modifications still go through the appropriate coder agent:

| Request Type | `/beggar:start` Required | Code Execution |
|--------------|----------------------|----------------|
| New feature / complex bug | ✅ Yes | Via coder agent |
| Simple bug fix / hotfix | ❌ Optional | Via coder agent |
| Config / env / constant change | ❌ Optional | Via coder-lite |
| Lint / type fix | ❌ Optional | Via coder-lite |
| Documentation (`.md`) | ❌ Optional | **Leader can edit directly** |

**Example:**
```
User: "Fix this typo in config.go"
Leader: Analyzes → tags [config_edit] → checks coder-guard
        → dispatches coder-lite → returns result
```

### Superpowers Integration

This multi-agent system is designed to work with [Superpowers](https://github.com/anthropics/superpowers) quality practices:

| Layer | Purpose | Example |
|-------|---------|---------|
| **Multi-Agent** | Who executes & cost control | Leader dispatches `coder-lite` for simple tasks, `coder-senior` for complex ones |
| **Superpowers** | How to do it right | Coder follows `test-driven-development` (red-green-refactor), `systematic-debugging` (root-cause first) |

**Relationship**: Superpowers provides the methodology (TDD, debugging, code review standards); the multi-agent system provides the execution architecture (who does what, with which model). They are complementary.

**Install Superpowers** (recommended):
```bash
# In CodeBuddy Code
/plugin superpowers
```

If Superpowers is not installed, the workflow still functions — Leader will perform the equivalent steps manually (e.g., self-guided brainstorming instead of `Skill("brainstorming")`).

## Notifications (Optional)

Beggar can send notifications to enterprise WeChat at key workflow nodes. Requires configuring `.codebuddy/skills/beggar-notify/notify.json` first.

> **Notification scope**: Currently triggered only at **exception / milestone** scenarios. Normal flow transitions do not send messages.

| Type | Trigger Scenario | Example |
|------|------------------|---------|
| **Milestone** | Phase 2 review passed, Phase 3 dev complete, workflow finished | ✅ Phase 2 review passed, entering development |
| **Exception** | 3rd review rejection, 3 review rounds failed, loop >5 rounds, auto-recovery exhausted, reviewer suspected error, final arbitration | ⚠️ 3rd rejection, user arbitration needed |

**Not covered**:
- Workflow start / phase transitions (normal flow does not notify)

### Hook Extension

Beggar leverages CodeBuddy's [Hook mechanism](https://www.codebuddy.ai/docs/cli/hooks) to cover additional notification scenarios without requiring extra plugins. Configured in `settings.json` and auto-injected by `setup.sh init`:

| Hook Event | Trigger | Notification |
|-----------|---------|--------------|
| `Notification` / `permission_prompt` | CodeBuddy pops up a permission dialog (e.g., Bash confirmation) | 🤖 Workflow checkpoint, needs your confirmation |
| `PreToolUse` / `Bash` | Sub-agent is about to execute a Bash command | ⚠️ Command execution requested, includes command details |
| `SubagentStop` | Sub-agent task completes | ✅ Task completed |

The hook script is located at `.codebuddy/hooks/beggar-notify-hook.py` and users can customize notification templates as needed.

To add start alerts or phase-transition notifications, modify `skills/beggar-workflow/SKILL.md` to insert notification calls at the corresponding nodes.

## Setup Commands

```bash
.codebuddy/setup.sh init              # Full initialization
.codebuddy/setup.sh show              # Show agent config
.codebuddy/setup.sh agent preset <n>  # Apply preset
.codebuddy/setup.sh agent inherit     # All agents inherit main model
.codebuddy/setup.sh agent custom <m>  # All agents use specified model
.codebuddy/setup.sh persona <theme>   # Switch persona theme (tech-legends/beggar-gang/sanguo/shuihu/genshin/default)
.codebuddy/setup.sh persona list      # List available themes
.codebuddy/setup.sh validate          # Check config integrity
.codebuddy/setup.sh diff [preset]     # Compare current vs preset
.codebuddy/setup.sh stats             # RTK token savings report
curl -fsSL <install-url> | bash       # Pull upstream updates (incremental sync)
```

## Agent Tools & Permissions

Each sub-agent is granted tools based on its role — **principle of least privilege**:

| Agent | Tools | Rationale |
|-------|-------|-----------|
| `architect` | Read, Write, Edit, Bash, Grep, Glob, WebFetch, WebSearch | Design requires reading code, writing design docs, searching for best practices, and running commands to validate assumptions. |
| `coder-senior` | Read, Write, Edit, Bash, Grep, Glob, WebFetch, WebSearch | Complex tasks often require looking up official docs, searching for patterns, and verifying third-party library APIs. |
| `coder-standard` | Read, Write, Edit, Bash, Grep, Glob | Standard tasks rely on model knowledge + codebase context. Search is unnecessary for well-understood patterns. |
| `coder-lite` | Read, Write, Edit, Bash, Grep, Glob | Simple CRUD/config tasks don't need external search. Keeps cost minimal and execution focused. |
| `reviewer` | Read, Grep, Glob, Bash | **Read-only** review. No Write/Edit to prevent unauthorized code changes — reviewer finds issues, coder fixes them. |
| `reviewer-b` | Read, Grep, Glob, Bash, WebFetch, WebSearch | Secondary review focuses on **technical soundness**, which requires searching to verify API usage, design patterns, and best practices. |
| `tester` | Read, Bash, Grep, Glob | **Pure validation** — compile, run tests, grep for errors. No Write/Edit; fixes go back to coder agents. |
| `recorder` | Read, Write, Edit, Bash, Grep, Glob | Knowledge capture requires writing to markdown files and editing documentation. Bash for archive operations. |
| `director` | Read, Glob, Grep, Bash, Agent | Read code and plans; Bash to fix design.md; Agent for delegation |

### Why no `use_skill`?

Sub-agents do **not** have `use_skill` permission. Skill invocation is the **Leader's responsibility** — the Leader decides which skill to call and when. Giving sub-agents `use_skill` would allow them to bypass Leader orchestration and invoke skills independently, breaking the workflow control model.

## ⚠️ IDE Users: Do Not Edit Agents in the Panel

If you installed beggar in **CodeBuddy IDE** (desktop app with web UI), **do not** use the IDE's "Agent Management" panel to edit beggar's sub-agents directly. The IDE's editor will:

1. **Convert tool names** from PascalCase (`Read`, `Write`) to snake_case (`read_file`, `write_to_file`)
2. **Add IDE-only runtime fields** (`agentMode`, `enabled`, `enabledAutoRun`) which are not part of the Markdown frontmatter spec
3. **Auto-expand the tool list** with IDE-recommended tools that beggar did not configure
4. **Overwrite the file format**, causing conflicts during incremental sync

**If you need to customize an agent**, create a new agent file directly in `.codebuddy/agents/`. The incremental sync mechanism in `install.sh` detects non-beggar files by SHA256 and preserves them during updates.

## Compatibility

- CodeBuddy Code (cbc CLI) v2.90+
- CodeBuddy IDE v2.90+ (agents work, but editing via IDE panel is not recommended)
- **Windows**: Supported via **Git Bash** or **WSL** (not PowerShell / cmd.exe)

  ⚠️ **Do NOT run `curl | bash` in PowerShell** — PowerShell's `curl` is an alias for `Invoke-WebRequest` and does not support Unix flags (`-fsSL`). The installation script is bash-only.

  ### Recommended: Git Bash (bundled with Git for Windows)

  ```bash
  # 1. Open Git Bash (right-click in any folder → "Git Bash Here")
  # 2. Run the same install command as Linux/macOS:
  curl -fsSL https://github.com/jagerzhang/beggar/raw/main/install.sh | bash

  # 3. Initialize in your project
  cd /c/Users/YourName/path/to/project
  beggar init
  ```

  ### Alternative: WSL (Windows Subsystem for Linux)

  ```bash
  # Install WSL if not already (run in PowerShell as Admin):
  wsl --install

  # Then inside WSL terminal, same as Linux:
  curl -fsSL https://github.com/jagerzhang/beggar/raw/main/install.sh | bash
  ```

  ### Notes
  - Python must be available in PATH (`python` or `python3`, both auto-detected)
  - RTK is auto-downloaded to `~/.local/bin/rtk.exe` on first init (filter mode only; full hook support requires WSL)
  - Git Bash terminal is required for `beggar init`, `beggar setup`, and all shell-based scripts

## License

MIT License — see [LICENSE](LICENSE) for details.