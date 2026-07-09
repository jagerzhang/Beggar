#!/usr/bin/env bats
# Bats tests for beggar core shell functions
#
# Prerequisites:
#   - bats-core installed (brew install bats-core / apt install bats)
#   - Python 3 available
#
# Run: bats dist/lib/tests/test_beggar.bats

load 'test_helper'

@test "resolve_model_alias: known alias resolves correctly" {
    result=$(resolve_model_alias "sonnet")
    [ "$result" = "claude-sonnet-4.6-1m" ]
}

@test "resolve_model_alias: empty input returns empty" {
    result=$(resolve_model_alias "")
    [ -z "$result" ]
}

@test "resolve_model_alias: unknown input passes through" {
    result=$(resolve_model_alias "some-unknown-model-xyz")
    [ "$result" = "some-unknown-model-xyz" ]
}

@test "resolve_model_alias: model id passes through" {
    result=$(resolve_model_alias "deepseek-v4-pro")
    [ "$result" = "deepseek-v4-pro" ]
}

@test "set_agent_model: writes model to agent file" {
    # Create a temp agent file
    local agent_file="$BATS_TMPDIR/test-agent.md"
    cat > "$agent_file" << 'EOF'
---
name: test-agent
description: Test agent
model: old-model
---

# Test Agent
EOF
    AGENTS_DIR="$BATS_TMPDIR" \
    set_agent_model "test-agent" "new-model"

    local model
    model=$(grep "^model:" "$agent_file" | sed 's/^model: *//')
    [ "$model" = "new-model" ]
}

@test "set_agent_model: creates agent from global template when missing" {
    # Create global agent template
    mkdir -p "$HOME/.codebuddy/agents"
    local global_agent="$HOME/.codebuddy/agents/test-global.md"
    cat > "$global_agent" << 'EOF'
---
name: test-global
description: Test global agent
model: global-model
---

# Test Global Agent
EOF

    # Set model in project dir
    AGENTS_DIR="$BATS_TMPDIR/project-agents" \
    set_agent_model "test-global" "project-model"

    local agent_file="$BATS_TMPDIR/project-agents/test-global.md"
    [ -f "$agent_file" ]

    local model
    model=$(grep "^model:" "$agent_file" | sed 's/^model: *//')
    [ "$model" = "project-model" ]

    # Cleanup
    rm -rf "$global_agent" "$BATS_TMPDIR/project-agents"
}

@test "set_agent_model: skips write when model matches global" {
    # Create global agent with model
    mkdir -p "$HOME/.codebuddy/agents"
    local global_agent="$HOME/.codebuddy/agents/test-skip.md"
    cat > "$global_agent" << 'EOF'
---
name: test-skip
description: Test skip agent
model: same-model
---
EOF

    # Try to set same model — should skip (no file created)
    AGENTS_DIR="$BATS_TMPDIR/skip-agents" \
    set_agent_model "test-skip" "same-model"

    [ ! -f "$BATS_TMPDIR/skip-agents/test-skip.md" ]

    # Cleanup
    rm -rf "$global_agent"
}

@test "setup_preset: invalid preset name exits with error" {
    MODELS_FILE="$BATS_TMPDIR/test-models.json"
    cat > "$MODELS_FILE" << 'EOF'
{
  "presets": {
    "test-preset": {
      "description": "Test",
      "config": {"architect": "model-a"}
    }
  }
}
EOF
    AGENTS_DIR="$BATS_TMPDIR/agents" \
    run setup_preset "nonexistent-preset"
    [ "$status" -eq 1 ]
}

@test "beggar-models.json is valid JSON" {
    local models_file="$PROJECT_DIR/dist/beggar-models.json"
    [ -f "$models_file" ]
    python3 -c "import json; json.load(open('$models_file'))"
}

@test "beggar-models.json validates against schema" {
    local models_file="$PROJECT_DIR/dist/beggar-models.json"
    local schema_file="$PROJECT_DIR/dist/beggar-models.schema.json"
    [ -f "$schema_file" ]

    # Try with jsonschema, skip if not installed
    if python3 -c "import jsonschema" 2>/dev/null; then
        python3 "$PROJECT_DIR/dist/lib/model_resolver.py" \
            --models "$models_file" validate --schema "$schema_file"
    else
        skip "jsonschema not installed"
    fi
}

@test "all agent .md files have required frontmatter" {
    local agents_dir="$PROJECT_DIR/dist/agents"
    [ -d "$agents_dir" ]

    for agent_file in "$agents_dir"/*.md; do
        [ -f "$agent_file" ]
        grep -q "^name:" "$agent_file"
        grep -q "^description:" "$agent_file"
        grep -q "^model:" "$agent_file"
    done
}

@test "shellcheck: lint.sh script exists" {
    [ -f "$PROJECT_DIR/scripts/lint.sh" ]
}

@test "model_resolver.py: resolve action works via CLI" {
    local models_file="$PROJECT_DIR/dist/beggar-models.json"
    local resolver="$PROJECT_DIR/dist/lib/model_resolver.py"

    result=$(python3 "$resolver" --models "$models_file" resolve --input "sonnet")
    [ "$result" = "claude-sonnet-4.6-1m" ]
}

@test "model_resolver.py: preset action outputs agent=model lines" {
    local models_file="$PROJECT_DIR/dist/beggar-models.json"
    local resolver="$PROJECT_DIR/dist/lib/model_resolver.py"

    result=$(python3 "$resolver" --models "$models_file" preset --name "balanced")
    echo "$result" | grep -q "architect="
    echo "$result" | grep -q "coder-senior="
    echo "$result" | grep -q "reviewer-b="
}

@test "_is_beggar_models_json: detects beggar format (has presets)" {
    local test_file="$BATS_TMPDIR/test-beggar-models.json"
    cat > "$test_file" << 'EOF'
{
  "presets": {"balanced": {"description": "test"}},
  "aliases": {}
}
EOF
    run _is_beggar_models_json "$test_file"
    [ "$status" -eq 0 ]
    rm -f "$test_file"
}

@test "_is_beggar_models_json: detects beggar format (has aliases only)" {
    local test_file="$BATS_TMPDIR/test-beggar-aliases.json"
    cat > "$test_file" << 'EOF'
{
  "aliases": {"sonnet": "claude-sonnet-4.6-1m"}
}
EOF
    run _is_beggar_models_json "$test_file"
    [ "$status" -eq 0 ]
    rm -f "$test_file"
}

@test "_is_beggar_models_json: rejects non-beggar format (CodeBuddy official)" {
    local test_file="$BATS_TMPDIR/test-codebuddy-models.json"
    cat > "$test_file" << 'EOF'
{
  "models": ["claude-sonnet-4.6-1m", "glm-5.2"],
  "default": "claude-sonnet-4.6-1m"
}
EOF
    run _is_beggar_models_json "$test_file"
    [ "$status" -eq 1 ]
    rm -f "$test_file"
}

@test "_is_beggar_models_json: rejects non-existent file" {
    run _is_beggar_models_json "$BATS_TMPDIR/nonexistent.json"
    [ "$status" -eq 1 ]
}

@test "_migrate_legacy_models_json: migrates beggar-format models.json to beggar-models.json" {
    local fake_codebuddy_dir="$BATS_TMPDIR/fake-codebuddy"
    mkdir -p "$fake_codebuddy_dir"

    # Create beggar-format models.json
    cat > "$fake_codebuddy_dir/models.json" << 'EOF'
{
  "presets": {"balanced": {"description": "test", "config": {"architect": "model-a"}}},
  "aliases": {"sonnet": "claude-sonnet-4.6-1m"}
}
EOF

    CODEBUDDY_DIR="$fake_codebuddy_dir" \
    BEGGAR_PROJECT_MODE="0" \
    run _migrate_legacy_models_json

    # Old file should be gone, new file should exist
    [ ! -f "$fake_codebuddy_dir/models.json" ]
    [ -f "$fake_codebuddy_dir/beggar-models.json" ]

    # Content should be preserved
    python3 -c "import json; d=json.load(open('$fake_codebuddy_dir/beggar-models.json')); assert 'presets' in d"

    rm -rf "$fake_codebuddy_dir"
}

@test "_migrate_legacy_models_json: does not touch non-beggar models.json" {
    local fake_codebuddy_dir="$BATS_TMPDIR/fake-codebuddy-safe"
    mkdir -p "$fake_codebuddy_dir"

    # Create CodeBuddy official format models.json
    cat > "$fake_codebuddy_dir/models.json" << 'EOF'
{
  "models": ["claude-sonnet-4.6-1m", "glm-5.2"],
  "default": "claude-sonnet-4.6-1m"
}
EOF

    CODEBUDDY_DIR="$fake_codebuddy_dir" \
    BEGGAR_PROJECT_MODE="0" \
    run _migrate_legacy_models_json

    # File should remain untouched
    [ -f "$fake_codebuddy_dir/models.json" ]
    [ ! -f "$fake_codebuddy_dir/beggar-models.json" ]

    rm -rf "$fake_codebuddy_dir"
}
