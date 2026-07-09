#!/usr/bin/env bats
# Test helper for beggar Bats tests

# Project root directory
PROJECT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../.." && pwd)"

# Setup: source all beggar lib modules with minimal env
setup() {
    export CODEBUDDY_DIR="$BATS_TMPDIR/.codebuddy"
    export AGENTS_DIR="$CODEBUDDY_DIR/agents"
    export MODELS_FILE="$PROJECT_DIR/dist/beggar-models.json"
    export USER_MODELS_FILE="$CODEBUDDY_DIR/user-models.json"
    export TOOLS_DIR="$CODEBUDDY_DIR/tools"
    export PERSONAS_FILE="$CODEBUDDY_DIR/personas.json"
    export PROJECT_DIR="$PROJECT_DIR"
    export BEGGAR_GLOBAL=0
    export LIB_DIR="$PROJECT_DIR/dist/lib"

    mkdir -p "$AGENTS_DIR"

    # Source lib modules (suppress output)
    source "$LIB_DIR/colors.sh" 2>/dev/null
    source "$LIB_DIR/utils.sh" 2>/dev/null
    source "$LIB_DIR/platform.sh" 2>/dev/null
    source "$LIB_DIR/models.sh" 2>/dev/null
    source "$LIB_DIR/preset.sh" 2>/dev/null
}
