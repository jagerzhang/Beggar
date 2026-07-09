#!/bin/bash
# Beggar persona theme management module
#
# Provides:
#   setup_persona_step()  - configure default persona during init (Step 6)
#   do_persona()          - CLI command to list/switch persona themes
#
# Dependencies (sourced by caller):
#   colors.sh             - print_* helpers
#   persona_expand.py     - Python module at $SCRIPT_DIR/lib/persona_expand.py
#   CODEBUDDY_DIR         - target .codebuddy directory
#   BEGGAR_GLOBAL         - "1" for global install
#   SCRIPT_DIR            - beggar dist/ directory

# Resolve SCRIPT_DIR if not provided by caller
: "${SCRIPT_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# ─── setup_persona_step ──────────────────────────────────────────────────
# Corresponds to setup.sh L1477-1575 (Step 6: 设置默认角色主题)
#
# Called during 'beggar init' to configure the default persona theme.
# Detects old-format persona-active.json and re-expands to full format.

setup_persona_step() {
    local codebuddy_dir="${1:-${CODEBUDDY_DIR:-$HOME/.codebuddy}}"
    local active_persona="$codebuddy_dir/persona-active.json"
    local personas_src="$codebuddy_dir/personas.json"
    [[ -f "$personas_src" ]] || personas_src="$HOME/.codebuddy/personas.json"

    if [[ ! -f "$personas_src" ]]; then
        print_warning "personas.json 不存在，跳过角色设置"
        return 0
    fi

    local needs_expand=false

    if [[ -f "$active_persona" ]]; then
        # Check if already in expanded format (has "roles" field)
        local has_roles
    has_roles=$("${PYTHON_CMD:-python3}" -c "
import json
with open('$active_persona') as f:
    data = json.load(f)
print('yes' if 'roles' in data else 'no')
" 2>/dev/null)

        if [[ "$has_roles" == "yes" ]]; then
            local current_theme
            current_theme=$(PERSONAS_FILE="$personas_src" \
                ACTIVE_PERSONA="$active_persona" \
                ACTION=get_current \
                "$PYTHON_CMD" "$SCRIPT_DIR/lib/persona_expand.py" 2>/dev/null)
            print_info "角色主题: $current_theme（已设置）"
        else
            needs_expand=true
            print_info "检测到旧格式 persona-active.json，重新展开..."
        fi
    else
        needs_expand=true
    fi

    if [[ "$needs_expand" == true ]]; then
        # Determine theme: preserve user's previous choice if old file exists
        local expand_theme="tech-legends"
        if [[ -f "$active_persona" ]]; then
            expand_theme=$("${PYTHON_CMD:-python3}" -c "
import json
with open('$active_persona') as f:
    print(json.load(f).get('theme', 'tech-legends'))
" 2>/dev/null)
        fi

        PERSONAS_FILE="$personas_src" \
            ACTIVE_PERSONA="$active_persona" \
            TARGET_THEME="$expand_theme" \
            ACTION=expand \
            "$PYTHON_CMD" "$SCRIPT_DIR/lib/persona_expand.py" 2>/dev/null

        print_success "角色主题: tech-legends（技术传奇 — 默认）"
        print_info "切换主题: .codebuddy/setup.sh persona list"
    fi
}

# ─── do_persona ───────────────────────────────────────────────────────────
# Corresponds to setup.sh L2490-2587 (do_persona CLI command)
#
# CLI usage: setup.sh persona [list|<theme>]
#   - No args or "list": list all available themes
#   - <theme>: switch to the specified theme

do_persona() {
    local theme="${1:-}"
    local codebuddy_dir="${CODEBUDDY_DIR:-$HOME/.codebuddy}"
    local personas_file="$codebuddy_dir/personas.json"
    [[ -f "$personas_file" ]] || personas_file="$HOME/.codebuddy/personas.json"
    local active_file="$codebuddy_dir/persona-active.json"

    if [[ ! -f "$personas_file" ]]; then
        print_error "personas.json 不存在，请先更新 beggar"
        return 1
    fi

    # ── No args or "list": display available themes ──
    if [[ -z "$theme" || "$theme" == "list" ]]; then
        print_header
        echo "可用角色主题："
        echo ""
        PERSONAS_FILE="$personas_file" \
            ACTIVE_PERSONA="$active_file" \
            ACTION=list \
            "$PYTHON_CMD" "$SCRIPT_DIR/lib/persona_expand.py" 2>/dev/null
        echo "切换: .codebuddy/setup.sh persona <theme>"
        echo "详情: 查看 PERSONAS.md"
        return 0
    fi

    # ── Validate theme exists ──
    if ! PERSONAS_FILE="$personas_file" \
        ACTIVE_PERSONA="$active_file" \
        TARGET_THEME="$theme" \
        ACTION=validate \
        "$PYTHON_CMD" "$SCRIPT_DIR/lib/persona_expand.py" 2>/dev/null; then
        print_error "主题 '$theme' 不存在"
        local available_themes
        available_themes=$("${PYTHON_CMD:-python3}" -c "
import json
with open('$personas_file') as f:
    data = json.load(f)
print(', '.join(data.get('themes', {}).keys()))
")
        echo "可用主题: $available_themes"
        return 1
    fi

    # ── Set active theme ──
    local theme_info
    theme_info=$(PERSONAS_FILE="$personas_file" \
        ACTIVE_PERSONA="$active_file" \
        TARGET_THEME="$theme" \
        ACTION=set \
        "$PYTHON_CMD" "$SCRIPT_DIR/lib/persona_expand.py" 2>/dev/null)

    print_success "已切换角色主题: $theme — $theme_info"
    echo ""
    echo "角色映射："
    PERSONAS_FILE="$personas_file" \
        ACTIVE_PERSONA="$active_file" \
        ACTION=show_current_config \
        "$PYTHON_CMD" "$SCRIPT_DIR/lib/persona_expand.py" 2>/dev/null
}
