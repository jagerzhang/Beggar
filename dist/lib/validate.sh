#!/bin/bash
# Beggar · validate | 验证 Agent 配置文件完整性

# ========================== 运维命令 ==========================

# validate: 验证 agent md frontmatter 完整性
do_validate() {
    print_header
    echo -e "验证 Agent 配置文件完整性：\n"

    local has_error=0
    for agent in "${AGENTS[@]}"; do
        local agent_file="$AGENTS_DIR/${agent}.md"
        if [[ ! -f "$agent_file" ]]; then
            print_error "$agent: 文件缺失 ($agent_file)"
            has_error=1
            continue
        fi

        # 检查 frontmatter 完整性
        local has_name has_desc has_model
        has_name=$(grep -c "^name:" "$agent_file")
        has_desc=$(grep -c "^description:" "$agent_file")
        has_model=$(grep -c "^model:" "$agent_file")

        if [[ "$has_name" == 0 || "$has_desc" == 0 || "$has_model" == 0 ]]; then
            print_error "$agent: frontmatter 不完整 (name=$has_name, description=$has_desc, model=$has_model)"
            has_error=1
        else
            print_success "$agent: frontmatter OK"
        fi
    done

    # 检查 beggar-models.json
    if ! "$PYTHON_CMD" -c "import json; json.load(open('$MODELS_FILE'))" 2>/dev/null; then
        print_error "beggar-models.json: JSON 格式错误"
        has_error=1
    else
        print_success "beggar-models.json: 格式 OK"
    fi

    # 检查 beggar-models.json 结构（JSON Schema 校验）
    local schema_file="${LIB_DIR}/../beggar-models.schema.json"
    if [[ -f "$schema_file" ]] && "$PYTHON_CMD" -c "import jsonschema" 2>/dev/null; then
        local schema_result
        schema_result=$("$PYTHON_CMD" "$LIB_DIR/model_resolver.py" --models "$MODELS_FILE" validate --schema "$schema_file" 2>&1)
        if [[ "$schema_result" == "valid" ]]; then
            print_success "beggar-models.json: Schema 校验通过"
        else
            print_warning "beggar-models.json: Schema 校验未通过"
            echo "$schema_result" | while IFS= read -r line; do
                echo "  $line"
            done
        fi
    else
        print_info "beggar-models.json: 跳过 Schema 校验（jsonschema 未安装或 schema 文件缺失）"
    fi

    # 检查平台兼容性
    local val_platform
    val_platform=$(detect_platform)
    print_info "检测平台: $val_platform"
    for agent in "${AGENTS[@]}"; do
        local agent_file="$AGENTS_DIR/${agent}.md"
        if [[ -f "$agent_file" ]]; then
            local agent_model
            agent_model=$(grep "^model:" "$agent_file" | sed 's/^model: *//')
            if [[ -n "$agent_model" && "$agent_model" != "inherit" ]]; then
                if ! check_model_platform "$agent_model" "$val_platform"; then
                    print_warning "$agent: 模型 $agent_model 不兼容当前平台 ($val_platform)"
                fi
            fi
        fi
    done

    # 检查 settings.json hook 路径有效性
    local settings_file="$CODEBUDDY_DIR/settings.json"
    if [[ -f "$settings_file" ]]; then
        local hook_path_issues
        hook_path_issues=$("$PYTHON_CMD" -c "
import json, sys
try:
    with open('$settings_file') as f:
        data = json.load(f)
    hooks = data.get('hooks', {})
    issues = []
    for event_name, matchers in hooks.items():
        for matcher in (matchers if isinstance(matchers, list) else []):
            for hook in matcher.get('hooks', []):
                cmd = hook.get('command', '')
                if 'beggar-notify-hook.py' in cmd:
                    # 检测旧版错误路径：被解析为绝对根目录的 / 或 \/
                    if '/.codebuddy/hooks' in cmd and ('\$HOME' not in cmd and '\$CODEBUDDY_PROJECT_DIR' not in cmd):
                        issues.append(f'{event_name}: {cmd}')
    if issues:
        print('\\n'.join(issues))
except Exception:
    pass
" 2>/dev/null)
        if [[ -n "$hook_path_issues" ]]; then
            print_error "settings.json 中检测到无效的 beggar hook 路径（被解析为绝对根目录）："
            echo "$hook_path_issues" | while IFS= read -r line; do
                echo "  $line"
            done
            print_info "请运行: ${YELLOW}.codebuddy/setup.sh init${NC} 自动修复"
            has_error=1
        fi
    fi

    # 检查 RTK
    if command -v rtk &>/dev/null; then
        print_success "RTK: 已安装(全局 $(which rtk))"
    else
        print_info "RTK: 未安装（可选，可手动安装: curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh）"
    fi

    echo ""
    if [[ "$has_error" == 0 ]]; then
        print_success "全部检查通过"
    else
        print_error "存在错误，请修复后重试"
        exit 1
    fi
}

# show_config: 显示当前 beggar 配置总览（调用 display.py）
show_config() {
    PLATFORM="$(detect_platform)" \
    CYAN="$CYAN" YELLOW="$YELLOW" NC="$NC" \
    AGENTS_DIR="$AGENTS_DIR" \
    MODELS_FILE="$MODELS_FILE" \
    USER_MODELS_FILE="$USER_MODELS_FILE" \
    CODEBUDDY_DIR="$CODEBUDDY_DIR" \
    BEGGAR_PROJECT_MODE="${BEGGAR_PROJECT_MODE:-0}" \
    PERSONAS_FILE="$PERSONAS_FILE" \
    "$PYTHON_CMD" "$LIB_DIR/display.py"
}
