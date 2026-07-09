#!/bin/bash
# beggar preset management utilities
#
# 所有 Python 子进程通过环境变量传参，禁止 shell 字符串插值（安全模式）
# 依赖调用方提供以下全局变量和函数：
#   - $AGENTS_DIR, $USER_MODELS_FILE, $MODELS_FILE, $HOME, $AGENTS
#   - $YELLOW, $CYAN, $NC
#   - print_info(), print_warning(), print_success(), print_error()
#   - resolve_model_alias(), set_agent_model(), _apply_user_overrides() (models.sh)
#   - detect_platform(), check_model_platform() (platform.sh)

# 模式：inherit（继承主面板模型）
setup_inherit() {
    for agent in "${AGENTS[@]}"; do
        set_agent_model "$agent" "inherit"
    done
    print_success "所有 Agent 已设置为 inherit（继承主面板模型）"
}

# 模式：custom（统一使用指定模型）
setup_custom() {
    local input="$1"
    if [[ -z "$input" ]]; then
        print_error "请指定模型名称: .codebuddy/setup.sh agent custom <model>"
        print_info "支持标准 ID (deepseek-v4-pro)、简写 (deepseek) 或 IDE 显示名 (deepseek v4 pro)"
        exit 1
    fi
    local model
    model=$(resolve_model_alias "$input")
    if [[ "$model" != "$input" ]]; then
        print_info "别名解析: $input → $model"
    fi
    for agent in "${AGENTS[@]}"; do
        set_agent_model "$agent" "$model"
    done
    print_success "所有 Agent 已设置为: $model"
}

# 用户自定义配置管理
setup_user() {
    local action="${1:-show}"
    case "$action" in
        show)
            if [[ -f "$USER_MODELS_FILE" ]]; then
                print_info "用户自定义配置 ($USER_MODELS_FILE):"
                USER_MODELS_FILE="$USER_MODELS_FILE" "$PYTHON_CMD" -c "
import json, os
try:
    with open(os.environ['USER_MODELS_FILE']) as f:
        data = json.load(f)
    preset = data.get('_meta', {}).get('based_on', 'unknown')
    print(f'  基于预设: {preset}')
    print('  覆盖项:')
    for agent, model in data.get('overrides', {}).items():
        print(f'    {agent}: {model}')
except Exception as e:
    print(f'  读取失败: {e}')
" 2>/dev/null
            else
                print_info "暂无用户自定义配置"
                print_info "创建方式: .codebuddy/setup.sh agent user edit"
            fi
            ;;
        edit|create)
            if [[ ! -f "$USER_MODELS_FILE" ]]; then
                # 创建模板
                cat > "$USER_MODELS_FILE" << 'USERMODEL'
{
  "_meta": {
    "description": "用户自定义模型配置（优先级高于预设）",
    "based_on": "balanced",
    "updated_at": ""
  },
  "overrides": {
    "architect": "",
    "coder-senior": "",
    "coder-standard": "",
    "coder-lite": "",
    "reviewer": "",
    "tester": "",
    "recorder": ""
  }
}
USERMODEL
                print_success "已创建模板: $USER_MODELS_FILE"
                print_info "请编辑 overrides 中的模型 ID，留空表示使用预设值"
            else
                print_info "编辑现有配置: $USER_MODELS_FILE"
            fi
            print_info "可用模型及倍率请查看: $MODELS_FILE"
            ;;
        clear|delete)
            if [[ -f "$USER_MODELS_FILE" ]]; then
                rm -f "$USER_MODELS_FILE"
                print_success "已删除用户自定义配置"
            else
                print_info "无用户自定义配置"
            fi
            ;;
        *)
            print_error "未知操作: $action"
            print_info "用法: .codebuddy/setup.sh agent user [show|edit|clear]"
            ;;
    esac
}

# 模式：preset（应用预设方案）
setup_preset() {
    local preset_name="$1"
    if [[ -z "$preset_name" ]]; then
        local current_platform
        current_platform=$(detect_platform)
        echo -e "可用预设方案（当前平台: ${CYAN}${current_platform}${NC}）："
        echo ""
        MODELS_FILE="$MODELS_FILE" PLATFORM="$current_platform" "$PYTHON_CMD" -c "
import json, os
with open(os.environ['MODELS_FILE']) as f:
    data = json.load(f)
platform = os.environ['PLATFORM']
for name, preset in data.get('presets', {}).items():
    p = preset.get('platform', 'both')
    marker = '  '
    if p != 'both' and p != platform:
        marker = '\u26a0 '
    print(f'  {marker}{name:14s} - {preset[\"description\"]}')
    for agent, model in preset['config'].items():
        print(f'                   {agent}: {model}')
    print()
" 2>/dev/null
        echo -e "用法: .codebuddy/setup.sh agent preset <name>"
        echo -e "提示: 标记 ⚠ 的预设在当前平台可能不完全兼容"
        exit 0
    fi

    local current_platform
    current_platform=$(detect_platform)

    # 检查预设平台兼容性
    local preset_platform
    preset_platform=$(MODELS_FILE="$MODELS_FILE" PRESET_NAME="$preset_name" "$PYTHON_CMD" -c "
import json, os
with open(os.environ['MODELS_FILE']) as f:
    data = json.load(f)
preset = data.get('presets', {}).get(os.environ['PRESET_NAME'], {})
print(preset.get('platform', 'both'))
" 2>/dev/null)

    if [[ "$preset_platform" != "both" && "$preset_platform" != "$current_platform" ]]; then
        print_warning "预设 '$preset_name' 标记为 $preset_platform 平台，当前检测到 $current_platform"
        if [[ "$preset_platform" == "cli" && "$current_platform" == "ide" ]]; then
            print_info "建议使用 economic-ide 或 balanced 预设"
        elif [[ "$preset_platform" == "ide" && "$current_platform" == "cli" ]]; then
            print_info "建议使用 economic 或 balanced 预设"
        fi
        print_info "继续应用...（部分模型可能不可用）"
        echo ""
    fi

    # 从 beggar-models.json 读取预设配置并应用
    # 使用 model_resolver.py CLI 替代 inline Python（BUG-2 修复：临时变量承接输出，避免 pipeline 静默吞错）
    local preset_output
    preset_output=$("$PYTHON_CMD" "$LIB_DIR/model_resolver.py" --models "$MODELS_FILE" preset --name "$preset_name" 2>&1) || {
        print_error "预设 '$preset_name' 不存在或解析失败"
        echo "$preset_output" >&2
        exit 1
    }

    echo "$preset_output" | while IFS='=' read -r agent model; do
        set_agent_model "$agent" "$model"
        # 平台兼容性提示
        if ! check_model_platform "$model" "$current_platform"; then
            print_warning "$agent → $model (⚠ 不兼容 $current_platform)"
        else
            print_info "$agent → $model"
        fi
    done

    print_success "已应用预设: $preset_name"
    # 应用用户自定义覆盖
    _apply_user_overrides
}
