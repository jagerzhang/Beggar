#!/bin/bash
# Beggar hooks management module
#
# Provides high-level wrappers around hooks_inject.py for:
#   inject_superpowers()        - detect & inject superpowers plugin
#   inject_beggar_hooks_step()  - inject beggar notification + RTK hooks
#   inject_all_hooks()          - combined superpowers + hooks injection
#   remove_beggar_hooks()       - remove beggar hooks from settings.json
#
# Dependencies (sourced by caller):
#   colors.sh         - print_* helpers
#   hooks_inject.py   - Python module at $SCRIPT_DIR/lib/hooks_inject.py
#   CODEBUDDY_DIR     - target .codebuddy directory
#   BEGGAR_GLOBAL     - "1" for global install, "0" for project install
#   SCRIPT_DIR        - beggar dist/ directory

# Resolve SCRIPT_DIR if not provided by caller
: "${SCRIPT_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# ─── Internal helpers ───────────────────────────────────────────────────

# Check if global ~/.codebuddy/settings.json already has beggar hooks
_global_has_beggar_hooks() {
    local global_settings="$HOME/.codebuddy/settings.json"
    if [[ ! -f "$global_settings" ]]; then
        return 1
    fi
    local result
    result=$(SETTINGS_FILE="$global_settings" ACTION=check_hooks_enabled \
        "$PYTHON_CMD" "$SCRIPT_DIR/lib/hooks_inject.py" 2>/dev/null)
    [[ "$result" == "true" ]]
}

# ─── inject_superpowers ─────────────────────────────────────────────────

inject_superpowers() {
    local settings_file="${1:-${CODEBUDDY_DIR:-$HOME/.codebuddy}/settings.json}"

    # Check if superpowers already enabled
    local superpowers_enabled=false
    if [[ -f "$settings_file" ]]; then
        superpowers_enabled=$(SETTINGS_FILE="$settings_file" ACTION=check \
            "$PYTHON_CMD" "$SCRIPT_DIR/lib/hooks_inject.py" 2>/dev/null)
    fi

    if [[ "$superpowers_enabled" == "true" ]]; then
        print_info "Superpowers 插件: 已在 settings.json 中启用 ✓"
        print_info "重启 CodeBuddy Code 后即可加载 Superpowers skills"
        return 0
    fi

    print_warning "Superpowers 插件未在 settings.json 中启用"
    print_info "已自动配置：$settings_file"
    print_info "请重启 CodeBuddy Code 加载插件，或手动执行：${YELLOW}/plugin superpowers${NC}"

    if [[ -f "$settings_file" ]]; then
        # Record that settings.json existed before beggar touched it
        local checksums_file="${CODEBUDDY_DIR:-$HOME/.codebuddy}/.beggar-checksums"
        if [[ -f "$checksums_file" ]]; then
            _sed_inplace "/^settings.json /d" "$checksums_file" 2>/dev/null || true
        fi
        echo "settings.json EXISTED" >> "$checksums_file"

        SETTINGS_FILE="$settings_file" ACTION=inject_superpowers \
            "$PYTHON_CMD" "$SCRIPT_DIR/lib/hooks_inject.py" 2>/dev/null \
            && print_info "已注入 Superpowers 配置到现有 settings.json"
    else
        cat > "$settings_file" << 'EOF'
{
  "enabledPlugins": {
    "superpowers@codebuddy-plugins-official": true
  }
}
EOF
        print_info "已创建默认 settings.json"
    fi
}

# ─── inject_beggar_hooks_step ───────────────────────────────────────────

inject_beggar_hooks_step() {
    local settings_file="${1:-${CODEBUDDY_DIR:-$HOME/.codebuddy}/settings.json}"

    # Ensure settings.json exists
    if [[ ! -f "$settings_file" ]]; then
        cat > "$settings_file" << 'EOF'
{
  "enabledPlugins": {
    "superpowers@codebuddy-plugins-official": true
  }
}
EOF
    fi

    # Determine hook command based on install mode
    local hook_cmd
    if [[ "${BEGGAR_GLOBAL:-0}" == "1" ]]; then
        hook_cmd='test -f "${HOME}/.codebuddy/hooks/beggar-notify-hook.py" && '"$PYTHON_CMD"' "${HOME}/.codebuddy/hooks/beggar-notify-hook.py" || exit 0'
    else
        hook_cmd='test -f .codebuddy/hooks/beggar-notify-hook.py && '"$PYTHON_CMD"' .codebuddy/hooks/beggar-notify-hook.py || exit 0'
    fi

    # Check if hooks are already enabled
    local hooks_enabled
    hooks_enabled=$(SETTINGS_FILE="$settings_file" ACTION=check_hooks_enabled \
        "$PYTHON_CMD" "$SCRIPT_DIR/lib/hooks_inject.py" 2>/dev/null)

    if [[ "$hooks_enabled" == "true" ]]; then
        print_info "Beggar hooks: 已配置 ✓"

        # Check for and fix broken/old hook paths
        local fix_result
        fix_result=$(SETTINGS_FILE="$settings_file" ACTION=fix_hooks \
            BEGGAR_GLOBAL="${BEGGAR_GLOBAL:-0}" \
            "$PYTHON_CMD" "$SCRIPT_DIR/lib/hooks_inject.py" 2>/dev/null)

        if [[ "$fix_result" == "fixed" ]]; then
            local fix_prefix
            if [[ "${BEGGAR_GLOBAL:-0}" == "1" ]]; then
                fix_prefix='$HOME/.codebuddy/hooks'
            else
                fix_prefix='$CODEBUDDY_PROJECT_DIR/.codebuddy/hooks'
            fi
            print_info "已修复 Hook 路径：旧版路径 / 错误路径 → $fix_prefix"
        fi
        return 0
    fi

    # Inject hooks (output may have multiple lines: injected, rtk_*, etc.)
    local result
    result=$(SETTINGS_FILE="$settings_file" ACTION=inject_hooks \
        HOOK_CMD="$hook_cmd" \
        BEGGAR_GLOBAL="${BEGGAR_GLOBAL:-0}" \
        "$PYTHON_CMD" "$SCRIPT_DIR/lib/hooks_inject.py" 2>/dev/null)

    while IFS= read -r line; do
        case "$line" in
            injected)
                print_info "Beggar hooks 已注入 settings.json"
                ;;
            no_change)
                # hooks already present, no write needed — skip to avoid triggering re-init
                ;;
            rtk_hook_injected)
                print_info "RTK hook 已注入 settings.json（自动转换 bash 命令）"
                ;;
            rtk_init_global)
                print_info "RTK 全局配置已初始化（rtk init -g）"
                ;;
            rtk_not_found)
                print_info "RTK 未安装，跳过 RTK hook 注入"
                print_info "如后续安装 RTK，可手动注入: rtk init -g"
                ;;
        esac
    done <<< "$result"
}

# ─── inject_all_hooks ───────────────────────────────────────────────────

inject_all_hooks() {
    local settings_file="${1:-${CODEBUDDY_DIR:-$HOME/.codebuddy}/settings.json}"
    inject_superpowers "$settings_file"
    inject_beggar_hooks_step "$settings_file"
}

# ─── remove_beggar_hooks ────────────────────────────────────────────────

remove_beggar_hooks() {
    local settings_file="${1:-${CODEBUDDY_DIR:-$HOME/.codebuddy}/settings.json}"

    if [[ ! -f "$settings_file" ]]; then
        return 0
    fi

    SETTINGS_FILE="$settings_file" ACTION=remove_hooks \
        "$PYTHON_CMD" "$SCRIPT_DIR/lib/hooks_inject.py" 2>/dev/null

    # Determine if settings.json was user-original or created by beggar
    local settings_existed=false
    local checksums_file="${CODEBUDDY_DIR:-$HOME/.codebuddy}/.beggar-checksums"
    if [[ -f "$checksums_file" ]]; then
        if grep -q "^settings.json EXISTED" "$checksums_file" 2>/dev/null; then
            settings_existed=true
        fi
    fi

    if [[ "$settings_existed" == true ]]; then
        print_info "settings.json 为用户原有文件，已取消 superpowers 注入（保留文件）"
    else
        local content
        content=$(cat "$settings_file" 2>/dev/null | tr -d '[:space:]')
        if [[ "$content" == "{}" || "$content" == "" ]]; then
            rm -f "$settings_file"
            print_info "settings.json 已为空，已删除"
        fi
    fi
}
