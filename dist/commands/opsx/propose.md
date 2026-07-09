---
name: OPSX: Propose
description: "Propose a new change - create it and generate all artifacts in one step"
argument-hint: "[command arguments]"
---

Propose a new change - create the change and generate all artifacts in one step.

I'll create a change with artifacts:
- proposal.md (what & why)
- design.md (how)
- tasks.md (implementation steps)

When ready to implement, run /opsx:apply

---

**Input**: The argument after `/opsx:propose` is the change name (kebab-case), OR a description of what the user wants to build.

**Parameters**:
- `--socratic` or `-s`: Enable Socratic exploration phase before generating artifacts. When this flag is present, the propose flow will first engage in a focused Q&A session (one question at a time) to clarify requirements, challenge assumptions, and ensure the proposal is well-grounded before creating any artifacts.

**Steps**

1. **If no input provided, ask what they want to build**

   Use the **AskUserQuestion tool** (open-ended, no preset options) to ask:
   > "What change do you want to work on? Describe what you want to build or fix."

   From their description, derive a kebab-case name (e.g., "add user authentication" → `add-user-auth`).

   **IMPORTANT**: Do NOT proceed without understanding what the user wants to build.

2. **Socratic exploration phase (if `--socratic` / `-s` flag is present)**

   Before generating any artifacts, enter a focused requirements clarification session:

   **Goal**: Through 3-7 rounds of one-question-at-a-time dialogue, ensure that:
   - The problem/need is clearly defined (not just the solution)
   - Key assumptions have been challenged
   - Scope boundaries are explicit
   - Major technical constraints are surfaced
   - Success criteria are understood

   **How it works**:
   a. Read the user's initial description and the relevant codebase context
   b. Ask ONE focused clarifying question — the most important unknown. Examples:
      - "你提到要加缓存——是因为遇到了性能问题，还是预防性的？有具体的延迟数据吗？"
      - "这个功能需要对所有用户开放，还是特定角色？"
      - "现有的 X 模块能复用吗，还是需要独立实现？"
   c. Wait for the user's answer
   d. Based on the answer, ask the next most important question
   e. Continue until you have enough clarity to write a solid proposal (typically 3-7 rounds)
   f. When ready, summarize the key decisions made during this dialogue:
      > "📋 基于我们的讨论，我整理了以下关键点：\n> - ...\n> 我现在开始生成 proposal、design 和 tasks。"

   **Socratic stance** (same as explore mode):
   - ONE question at a time — never stack multiple questions
   - Challenge assumptions — "Why does this need to be X?" "What if we didn't Y?"
   - Investigate codebase when relevant — ground questions in actual code, not theory
   - Be adaptive — follow interesting threads, don't stick to a rigid checklist

   **When to skip** (even with `--socratic`):
   - User has already provided very detailed requirements (e.g., copy-pasted a spec)
   - User explicitly says "直接生成，不用问了"
   - In these cases, acknowledge and proceed to artifact generation

   After this phase, continue to step 3 (Create the change directory).

3. **Create the change directory**
   ```bash
   openspec new change "<name>"
   ```
   This creates a scaffolded change at `openspec/changes/<name>/` with `.openspec.yaml`.

4. **Get the artifact build order**
   ```bash
   openspec status --change "<name>" --json
   ```
   Parse the JSON to get:
   - `applyRequires`: array of artifact IDs needed before implementation (e.g., `["tasks"]`)
   - `artifacts`: list of all artifacts with their status and dependencies

5. **Create artifacts in sequence until apply-ready**

   Use the **TodoWrite tool** to track progress through the artifacts.

   **If Socratic phase was completed (step 2)**, use the clarified requirements and decisions as primary input when generating artifacts. The quality of artifacts should be noticeably higher because ambiguities were resolved upfront.

   Loop through artifacts in dependency order (artifacts with no pending dependencies first):

   a. **For each artifact that is `ready` (dependencies satisfied)**:
      - Get instructions:
        ```bash
        openspec instructions <artifact-id> --change "<name>" --json
        ```
      - The instructions JSON includes:
        - `context`: Project background (constraints for you - do NOT include in output)
        - `rules`: Artifact-specific rules (constraints for you - do NOT include in output)
        - `template`: The structure to use for your output file
        - `instruction`: Schema-specific guidance for this artifact type
        - `outputPath`: Where to write the artifact
        - `dependencies`: Completed artifacts to read for context
      - Read any completed dependency files for context
      - Create the artifact file using `template` as the structure
      - Apply `context` and `rules` as constraints - but do NOT copy them into the file
      - Show brief progress: "Created <artifact-id>"

   b. **Continue until all `applyRequires` artifacts are complete**
      - After creating each artifact, re-run `openspec status --change "<name>" --json`
      - Check if every artifact ID in `applyRequires` has `status: "done"` in the artifacts array
      - Stop when all `applyRequires` artifacts are done

   c. **If an artifact requires user input** (unclear context):
      - Use **AskUserQuestion tool** to clarify
      - Then continue with creation

6. **Show final status**
   ```bash
   openspec status --change "<name>"
   ```

**Output**

After completing all artifacts, summarize:
- Change name and location
- List of artifacts created with brief descriptions
- What's ready: "All artifacts created! Ready for implementation."
- Prompt: "Run `/opsx:apply` to start implementing."

**Artifact Creation Guidelines**

- Follow the `instruction` field from `openspec instructions` for each artifact type
- The schema defines what each artifact should contain - follow it
- Read dependency artifacts for context before creating new ones
- Use `template` as the structure for your output file - fill in its sections
- **IMPORTANT**: `context` and `rules` are constraints for YOU, not content for the file
  - Do NOT copy `<context>`, `<rules>`, `<project_context>` blocks into the artifact
  - These guide what you write, but should never appear in the output
- **Coding standards awareness**: When creating `design.md` and `tasks.md`, reference the relevant coding standards from `.codebuddy/rules/` (or `$HOME/.codebuddy/rules/` in global install mode) for the target language(s). For example:
  - If designing a Go feature → mention that implementation must follow `Go代码规范.mdc` (80-line function limit, exported identifiers need doc comments, etc.)
  - If designing a Python feature → note PEP8, type hints requirement, broad-except rules
  - If designing a frontend feature → note TypeScript conventions (ESM, `===`, 2-space indent)
  - This ensures the design artifacts carry forward coding constraints into the implementation phase

**Guardrails**
- Create ALL artifacts needed for implementation (as defined by schema's `apply.requires`)
- Always read dependency artifacts before creating a new one
- If context is critically unclear, ask the user - but prefer making reasonable decisions to keep momentum
- If a change with that name already exists, ask if user wants to continue it or create a new one
- Verify each artifact file exists after writing before proceeding to next
- **Socratic mode (`--socratic`)**: Ask ONE question at a time, never stack questions. 3-7 rounds is the sweet spot — enough to clarify, not so many that momentum dies.
- **Socratic mode**: Don't ask about things you can investigate yourself. Check the codebase first, then ask about intent/priorities/constraints that only the user knows.
- **Socratic mode**: If the user says "直接生成" or provides exhaustive detail, respect that and skip the Q&A.
