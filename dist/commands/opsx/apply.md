---
name: OPSX: Apply
description: "Implement tasks from an OpenSpec change (Experimental)"
argument-hint: "[command arguments]"
---

Implement tasks from an OpenSpec change.

**Input**: Optionally specify a change name (e.g., `/opsx:apply add-auth`). If omitted, check if it can be inferred from conversation context. If vague or ambiguous you MUST prompt for available changes.

**Steps**

1. **Select the change**

   If a name is provided, use it. Otherwise:
   - Infer from conversation context if the user mentioned a change
   - Auto-select if only one active change exists
   - If ambiguous, run `openspec list --json` to get available changes and use the **AskUserQuestion tool** to let the user select

   Always announce: "Using change: <name>" and how to override (e.g., `/opsx:apply <other>`).

2. **Check status to understand the schema**
   ```bash
   openspec status --change "<name>" --json
   ```
   Parse the JSON to understand:
   - `schemaName`: The workflow being used (e.g., "spec-driven")
   - Which artifact contains the tasks (typically "tasks" for spec-driven, check status for others)

3. **Get apply instructions**

   ```bash
   openspec instructions apply --change "<name>" --json
   ```

   This returns:
   - Context file paths (varies by schema)
   - Progress (total, complete, remaining)
   - Task list with status
   - Dynamic instruction based on current state

   **Handle states:**
   - If `state: "blocked"` (missing artifacts): show message, suggest using `/opsx:continue`
   - If `state: "all_done"`: congratulate, suggest archive
   - Otherwise: proceed to implementation

4. **Read context files**

   Read the files listed in `contextFiles` from the apply instructions output.
   The files depend on the schema being used:
   - **spec-driven**: proposal, specs, design, tasks
   - Other schemas: follow the contextFiles from CLI output

5. **Load coding standards and tool rules**

   Before writing any code, identify which languages will be touched by the tasks and load the corresponding coding standards from `.codebuddy/rules/`.
   If the project-level `.codebuddy/rules/` does not exist (global install mode), check `$HOME/.codebuddy/rules/` instead.

   **Language → Rule file mapping:**

   | File Extensions | Rule File | Key Highlights |
   |----------------|-----------|----------------|
   | `*.go` | `Go代码规范.mdc` | gofmt, 80行函数限制, 800行文件限制, 导出必须注释, 驼峰命名 |
   | `*.py` | `Python代码规范.mdc` | PEP8, 120字符行宽, `except Exception: # pylint: disable=broad-except`, 类型提示 |
   | `*.ts,*.tsx,*.vue,*.js,*.jsx` | `TypeScript代码规范.mdc` | ESM import, `===`, 2空格缩进, camelCase, 分号必须 |
   | `*.css,*.scss` | `CSS代码规范.mdc` | CSS 编码格式规范 |
   | `*.java` | `Java开发规范.mdc` | Java 编码标准 |
   | `*.sql` | `SQL官方规范.mdc` | SQL 编写规范 |
   | `*.cpp,*.h,*.hpp,*.c,*.cc` | `C++代码规范.mdc` | C++ 编码标准 |
   | tRPC 框架代码 | `tRPC开发规范.mdc` | tRPC-Go/Cpp/Python/Java 框架规范 |

   **How to load:**
   a. Scan the task list — determine which files/modules will be created or modified
   b. Read the matching rule file(s) using `read_file`:
      ```
      .codebuddy/rules/beggar-Go代码规范.mdc        # if touching *.go
      .codebuddy/rules/beggar-Python代码规范.mdc     # if touching *.py
      .codebuddy/rules/beggar-TypeScript代码规范.mdc # if touching *.ts/*.vue/*.js
      ```
   c. Keep the rules in context — they are **mandatory constraints** during implementation
   d. If a task spans multiple languages (e.g., Go backend + Vue frontend), load ALL relevant rule files

   **RTK** (optional): If RTK is installed, the PreToolUse hook automatically compresses bash command output. Write native commands directly; no manual `rtk` prefix needed. Fall back to native commands when compressed output lacks detail for debugging.

6. **Show current progress**

   Display:
   - Schema being used
   - Progress: "N/M tasks complete"
   - Remaining tasks overview
   - Dynamic instruction from CLI

7. **Implement tasks (loop until done or blocked)**

   **Quality Mode Selection**: Before starting, assess the tasks:
   - If **3+ independent tasks** remain and they touch different files/modules → use **Parallel Agent Mode**
   - Otherwise → use **Sequential Mode** (default)

   ---

   ### Sequential Mode (default)

   For each pending task:
   - Show which task is being worked on
   - **Strictly follow the loaded coding standards** (step 5) for the language being written:
     - Go: gofmt formatting, exported identifiers must have comments, function ≤ 80 lines, file ≤ 800 lines
     - Python: PEP8, type hints, `except Exception:  # pylint: disable=broad-except`
     - TypeScript/Vue: ESM imports, `===`, 2-space indent, semicolons required
     - Other languages: follow the corresponding loaded rule file
   - **Apply TDD when the task involves code changes with testable behavior:**
     1. Write a failing test first (RED) — test the expected behavior
     2. Run the test to verify it fails for the right reason
     3. Write minimal implementation code to pass the test (GREEN)
     4. Refactor if needed, keeping tests green
     - *Skip TDD for*: config changes, documentation, pure refactoring of existing tested code, UI-only changes without logic
   - Keep changes minimal and focused
   - Mark task complete in the tasks file: `- [ ]` → `- [x]`
   - Continue to next task

   ### Parallel Agent Mode (3+ independent tasks)

   When multiple tasks are independent (different files, different modules, no shared state):
   1. Group tasks by independence — tasks touching the same files go in the same group
   2. Dispatch one **Task tool** (subagent) per group:
      - Each agent prompt includes: the task description, relevant context files, TDD requirement
      - Constraint: "Only modify files related to your assigned task"
   3. When agents return, review results for conflicts
   4. Run full test suite to verify integration
   5. Mark all completed tasks in the tasks file

   ---

   **Pause if:**
   - Task is unclear → ask for clarification
   - Implementation reveals a design issue → suggest updating artifacts
   - Error or blocker encountered → report and wait for guidance
   - User interrupts
   - **Bug encountered during implementation** → apply systematic debugging: investigate root cause before fixing (don't guess-and-fix)

8. **Quality verification before marking complete**

   After all tasks are done (or at natural checkpoints every 3-5 tasks):

   a. **Run project tests:**
      - Determine the correct test command for the sub-project being modified
      - Run tests and verify all pass
      - If new tests were added via TDD, confirm they're included

   b. **Spec compliance check:**
      - Re-read the design.md and specs from context files
      - Verify implementation matches the design decisions
      - Flag any deviations: "Design says X but implementation does Y"

   c. **Self code review** (for significant changes, 3+ files modified):
      - Review the diff of all changes made
      - Check for: missed error handling, hardcoded values, missing type annotations, broad exceptions without `# pylint: disable=broad-except` (Python)
      - Check Go code reuses existing middleware (`ExtractToken`, `HashSecret`, `BackendAuthAdapter`) before creating new ones
      - **Coding standards compliance**: Verify all changes comply with the loaded rule files (step 5):
        - Go: exported functions/types have doc comments? Function/file length within limits? gofmt-compatible formatting?
        - Python: PEP8 compliant? Type hints present? Imports ordered correctly?
        - TypeScript: `const`/`let` used correctly? No `var`? Semicolons present? `===` used?
      - Report findings and fix issues before proceeding

   **IMPORTANT**: Do NOT claim "all tasks complete" without running verification. Evidence before assertions.

9. **On completion or pause, show status**

   Display:
   - Tasks completed this session
   - Overall progress: "N/M tasks complete"
   - If all done: suggest archive
   - If paused: explain why and wait for guidance

**Output During Implementation**

```
## Implementing: <change-name> (schema: <schema-name>)

Working on task 3/7: <task description>
[...implementation happening...]
✓ Task complete

Working on task 4/7: <task description>
[...implementation happening...]
✓ Task complete
```

**Output On Completion**

```
## Implementation Complete

**Change:** <change-name>
**Schema:** <schema-name>
**Progress:** 7/7 tasks complete ✓

### Quality Summary
- Tests: ✓ All passing (N tests)
- TDD: Applied to M tasks
- Spec compliance: ✓ Verified against design.md
- Code review: ✓ Self-reviewed (or N/A if < 3 files)

### Completed This Session
- [x] Task 1
- [x] Task 2
...

All tasks complete! You can archive this change with `/opsx:archive`.
```

**Output On Pause (Issue Encountered)**

```
## Implementation Paused

**Change:** <change-name>
**Schema:** <schema-name>
**Progress:** 4/7 tasks complete

### Issue Encountered
<description of the issue>

**Options:**
1. <option 1>
2. <option 2>
3. Other approach

What would you like to do?
```

**Guardrails**
- Keep going through tasks until done or blocked
- Always read context files before starting (from the apply instructions output)
- If task is ambiguous, pause and ask before implementing
- If implementation reveals issues, pause and suggest artifact updates
- Keep code changes minimal and scoped to each task
- Update task checkbox immediately after completing each task
- Pause on errors, blockers, or unclear requirements - don't guess
- Use contextFiles from CLI output, don't assume specific file names
- **Apply TDD for tasks with testable behavior** - write failing test first, then implement
- **Never claim completion without running tests** - evidence before assertions
- **Use parallel agents for 3+ independent tasks** - dispatch via Task tool, review for conflicts
- **Systematic debugging only** - when a bug appears, investigate root cause before fixing; no guess-and-fix
- **Respect project conventions** — Python: `except Exception:  # pylint: disable=broad-except`; Go: reuse existing middleware before creating new ones
- **Load coding standards before writing code** — always read the matching `.codebuddy/rules/` file for the language being written; these are mandatory, not suggestions
- **Use native shell commands** — write native commands directly; if RTK is installed, the PreToolUse hook auto-compresses output. Fall back to native when debugging needs full output

**Fluid Workflow Integration**

This skill supports the "actions on a change" model:

- **Can be invoked anytime**: Before all artifacts are done (if tasks exist), after partial implementation, interleaved with other actions
- **Allows artifact updates**: If implementation reveals design issues, suggest updating artifacts - not phase-locked, work fluidly

**Superpowers Integration**

This skill integrates the following Superpowers capabilities:

| Superpowers Skill | When Used | How Integrated |
|---|---|---|
| `test-driven-development` | Each task with testable behavior | RED → GREEN → REFACTOR cycle |
| `dispatching-parallel-agents` | 3+ independent tasks | Task tool dispatches parallel agents |
| `verification-before-completion` | After all tasks / every 3-5 tasks | Tests + spec compliance + code review |
| `systematic-debugging` | Bug encountered during implementation | Root cause investigation before fix |

**Rules Integration**

| Rule | Source | When Loaded | How Used |
|---|---|---|---|
| Coding standards (Go/Python/TS/CSS/Java/SQL/C++) | `.codebuddy/rules/beggar-<lang>代码规范.mdc` | Step 5, before implementation | Mandatory constraints during code writing + self code review |
| tRPC framework rules | `.codebuddy/rules/beggar-tRPC开发规范.mdc` | Step 5, when tRPC code is involved | Framework-specific patterns and conventions |
| RTK token optimization | `.codebuddy/rules/beggar-rtk.mdc` | Optional | If RTK installed, PreToolUse hook auto-compresses bash output (60-90% savings) |

These are embedded as workflow steps, not invoked as separate skills — the quality practices are woven into the implementation flow.
