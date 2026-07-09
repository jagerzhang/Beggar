#!/bin/bash
# beggar model management utilities
#
# 所有 Python 子进程通过环境变量传参，禁止 shell 字符串插值（安全模式）
# 依赖调用方提供以下全局变量和函数：
#   - $MODELS_FILE, $USER_MODELS_FILE, $AGENTS_DIR, $PROJECT_DIR, $HOME
#   - $BEGGAR_GLOBAL, $YELLOW, $NC
#   - print_info(), print_warning(), print_success(), print_error()

# 解析模型别名：输入可能是 IDE 显示名、简写或标准 ID
resolve_model_alias() {
    local input="$1"
    if [[ -z "$input" ]]; then
        echo ""
        return
    fi

    # 使用 model_resolver.py CLI 替代 inline Python（安全模式：CLI args 传参）
    local resolved
    resolved=$("$PYTHON_CMD" "$LIB_DIR/model_resolver.py" --models "$MODELS_FILE" resolve --input "$input" 2>/dev/null)

    if [[ -n "$resolved" ]]; then
        echo "$resolved"
    else
        echo "$input"
    fi
}

# 设置单个 agent 的 model 字段
set_agent_model() {
    local agent="$1"
    local model="$2"
    local agent_file="$AGENTS_DIR/${agent}.md"

    if [[ ! -f "$agent_file" ]]; then
        # 项目隔离模式：检查全局同名 agent，model 相同则跳过（复用全局，不写项目文件）
        local global_agent="$HOME/.codebuddy/agents/${agent}.md"
        if [[ -f "$global_agent" ]]; then
            local global_model
            global_model=$(grep "^model:" "$global_agent" | sed 's/^model: *//')
            if [[ "$global_model" == "$model" ]]; then
                return 0  # model 与全局相同，无需写项目文件
            fi
            mkdir -p "$AGENTS_DIR"
            cp "$global_agent" "$agent_file"
        else
            print_warning "Agent 模板不存在: $agent_file（全局也无）"
            return 1
        fi
    fi

    # 使用 sed 替换 frontmatter 中的 model 行（跨平台兼容）
    if grep -q "^model:" "$agent_file"; then
        _sed_inplace "s/^model:.*/model: $model/" "$agent_file"
    fi
}

# 应用用户自定义模型覆盖（优先级高于预设）
_apply_user_overrides() {
    if [[ ! -f "$USER_MODELS_FILE" ]]; then
        return 0
    fi

    local overrides
    overrides=$("$PYTHON_CMD" "$LIB_DIR/model_resolver.py" --models "$MODELS_FILE" overrides --user-models "$USER_MODELS_FILE" 2>/dev/null)

    if [[ -z "$overrides" ]]; then
        return 0
    fi

    print_info "检测到用户自定义配置，应用覆盖..."
    while IFS='=' read -r agent model; do
        if [[ -n "$agent" && -n "$model" ]]; then
            set_agent_model "$agent" "$model"
            print_info "  $agent → $model (用户自定义)"
        fi
    done <<< "$overrides"
}

# 检查当前 Leader 模型与 preset 推荐是否一致
_check_leader_model() {
    local preset_name="${1:-balanced}"
    local auto_switch="${2:-}"
    local global_settings="$HOME/.codebuddy/settings.json"

    # 写入 settings.json model 字段的统一函数（原子写入）— 提前定义，确保所有分支可用
    _write_model_to_settings() {
        local target_model="$1"
        [[ -z "$target_model" ]] && return 1   # 空模型直接拒绝，防写空
        SETTINGS_FILE="$global_settings" MODEL_VALUE="$target_model" "$PYTHON_CMD" -c "
import json, sys, os, tempfile
sf = os.environ['SETTINGS_FILE']
model_val = os.environ['MODEL_VALUE']
with open(sf) as f:
    data = json.load(f)
data['model'] = model_val
dir_name = os.path.dirname(sf)
tmp = tempfile.NamedTemporaryFile(mode='w', dir=dir_name, prefix='.', suffix='.tmp', delete=False)
try:
    json.dump(data, tmp, indent=2, ensure_ascii=False)
    tmp.flush()
    os.fsync(tmp.fileno())
finally:
    tmp.close()
os.replace(tmp.name, sf)
print('ok')
" 2>/dev/null | grep -q 'ok' 2>/dev/null
    }

    # 获取 preset 推荐的 leader_model — 提前获取，确保所有分支可用
    local recommended_model
    recommended_model=$("$PYTHON_CMD" "$LIB_DIR/model_resolver.py" --models "$MODELS_FILE" leader --name "$preset_name" 2>/dev/null | head -1 | tr -d '\n\r')

    if [[ -z "$recommended_model" ]]; then
        return 0
    fi

    # 获取当前 Leader 模型（直接读 settings.json model 字段）
    print_info "正在检测当前面板模型..."
    local current_model
    current_model=$("$PYTHON_CMD" -c "
import json, sys
try:
    with open('$global_settings') as f:
        data = json.load(f)
    print(data.get('model', ''))
except Exception:
    pass
" 2>/dev/null | head -1 | tr -d '\n\r')

    if [[ -z "$current_model" ]]; then
        # 无模型配置（新装或模型被清除），自动写入推荐模型
        if [[ "$auto_switch" == "--auto-switch" ]]; then
            if _write_model_to_settings "$recommended_model"; then
                print_success "已设置面板模型: $recommended_model"
            else
                print_warning "设置失败，请手动执行 /model $recommended_model"
            fi
        else
            print_info "  建议执行: ${YELLOW}/model $recommended_model${NC}"
        fi
        return 0
    fi

    # 对比
    if [[ "$current_model" == "$recommended_model" ]]; then
        print_success "当前面板模型与 $preset_name 预设推荐一致 ($current_model)"
    else
        print_warning "当前面板模型: $current_model"
        print_info "  $preset_name 预设推荐: $recommended_model"

        # init 流程中自动询问切换
        if [[ "$auto_switch" == "--auto-switch" ]]; then
            if [[ "$BEGGAR_GLOBAL" == "1" ]] || [ ! -t 0 ]; then
                # 全局安装或非交互式：直接写 settings.json
                if _write_model_to_settings "$recommended_model"; then
                    print_success "已设置面板模型: $recommended_model"
                else
                    print_warning "设置失败，请手动执行 /model $recommended_model"
                fi
            else
                # 交互式终端，询问用户确认
                echo ""
                read -r -p "  是否切换面板模型到 $recommended_model? [Y/n] " answer
                if [[ -z "$answer" || "$answer" =~ ^[Yy]$ ]]; then
                    if _write_model_to_settings "$recommended_model"; then
                        print_success "已设置面板模型: $recommended_model"
                    else
                        print_error "设置失败，请手动执行 /model $recommended_model"
                    fi
                else
                    print_info "跳过切换，保持当前模型 $current_model"
                fi
            fi
        else
            print_info "  建议执行: ${YELLOW}/model $recommended_model${NC}"
        fi
    fi
}

# setup_agent: agent 命令路由（beggar agent [mode] [args]）
setup_agent() {
    local mode="${1:-}"
    case "$mode" in
        "")        interactive_setup ;;
        inherit)   setup_inherit ;;
        custom)    setup_custom "$2" ;;
        user)      setup_user "$2" "$3" ;;
        preset)    setup_preset "$2" ;;
        show)      ;;
        *)         print_error "未知模式: $mode"; show_help ;;
    esac
    echo ""
    show_config
}
