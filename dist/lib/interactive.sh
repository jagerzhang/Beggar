#!/bin/bash
# Beggar · interactive | 用户交互入口：帮助信息 + 交互式选择

show_help() {
    "$PYTHON_CMD" "$LIB_DIR/banner.py"
    cat << 'EOF'
用法：
  beggar [--global|-g] [--project|-p] init       初始化环境
  beggar [--global|-g] [--project|-p] quickstart  交互式配置向导（推荐首次使用）
  beggar [--global] [--project] agent [mode]      配置 Agent 模型
  beggar [--global] [--project] show              显示当前配置
  beggar [--global] [--project] persona [theme]   切换角色主题
  beggar [--global] [--project] notify <msg>      发送通知
  beggar setup shell                              配置 cbc CLI 启动别名
  beggar validate / diff / update / reinstall / uninstall / stats

安装模式：
  --global / -g    全局安装到 ~/.codebuddy/（所有项目共用）
  --project / -p   项目级安装到当前目录 .codebuddy/
  项目配置覆盖全局配置（Agent 模型、角色、通知等）

初始化（新项目首次使用）：
  .codebuddy/setup.sh init             一键完成环境初始化

Agent 模型配置模式：
  .codebuddy/setup.sh agent                  交互式选择
  .codebuddy/setup.sh agent inherit          所有 Agent 继承主面板模型
  .codebuddy/setup.sh agent custom <model>   统一使用指定模型
  .codebuddy/setup.sh agent preset <name>    应用预设方案
  .codebuddy/setup.sh agent user [show|edit|clear]  用户自定义配置

用户自定义配置：
  创建 .codebuddy/user-models.json 持久化自定义模型
  优先级高于预设，可基于某个预设然后覆盖特定 agent

  示例:
    .codebuddy/setup.sh agent user edit
    # 编辑 user-models.json 后:
    .codebuddy/setup.sh agent preset balanced  # 会自动应用用户覆盖

预设方案：
  economic      经济模式/CLI（V4-Pro 架构+代码 + Hy3 审查/测试，节省 >95%）
  balanced      平衡模式/CLI（GLM-5.2 架构 + V4 代码 + 三厂商覆盖，节省 >70%）
  quality       质量优先（Opus 编排 + Sonnet 代码 + Kimi/Gemini 审查，节省 >68%）

交互式配置向导（推荐首次使用）：
  .codebuddy/setup.sh quickstart          从零开始完成全部配置
  引导流程：平台检测 → 预设推荐 → 通知配置 → 角色主题 → Shell 别名
  结束后输出常用命令速查，适用于新手和全面重新配置场景

Shell 别名配置（cbc CLI 快速启动）：
  .codebuddy/setup.sh setup shell         引导式配置 cbc 启动别名
  支持模式：全程自动 / 跳过安全确认 / 静默拦截 / 自定义逐项选择
  自动检测 ~/.zshrc / ~/.bashrc 并写入，避免重复手动输入参数


模型别名（IDE/CLI 兼容）：
支持标准 ID:    deepseek-v4-pro, kimi-k2.7, glm-5.2
  支持简写:       deepseek, kimi, glm, hy3, minimax
  支持 IDE 显示名: "deepseek v4 pro", "kimi k2.6", "glm 5.1"

示例：
  beggar init
  beggar quickstart
  beggar agent inherit
  beggar agent preset balanced
  beggar agent custom "kimi k2.6"
  beggar persona sangguo
  beggar persona list
  beggar show
  beggar setup shell
  beggar reinstall

项目覆盖全局：
  beggar -p agent preset economic   # 当前项目用经济模式
  beggar -p persona genshin         # 当前项目用提瓦特主题
EOF
}

# 交互式选择
interactive_setup() {
    print_header
    echo -e "选择 Agent 模型配置方案：\n"
    echo -e "  ${GREEN}0)${NC} ${YELLOW}economic${NC}  - 经济模式（V4-Pro 架构+代码 + Hy3 审查/测试，节省 >95%）"
    echo -e "  ${GREEN}1)${NC} ${YELLOW}balanced${NC}  - 平衡模式（推荐，GLM-5.2 架构 + V4 代码 + 三厂商覆盖，节省 >70%）"
    echo -e "  ${GREEN}2)${NC} ${YELLOW}quality${NC}   - 质量优先（Opus 编排 + Sonnet 代码 + Kimi/Gemini 审查，节省 >68%）"
    echo -e "  ${GREEN}3)${NC} ${YELLOW}inherit${NC}   - 继承主面板模型（跟随 /model 切换）"
    echo -e "  ${GREEN}4)${NC} ${YELLOW}custom${NC}    - 统一使用指定模型"
    if [[ -f "$USER_MODELS_FILE" ]]; then
        echo -e "  ${GREEN}5)${NC} ${YELLOW}user${NC}      - 使用用户自定义配置"
    else
        echo -e "  ${GREEN}5)${NC} ${YELLOW}user${NC}      - 创建用户自定义配置"
    fi
    echo ""
    echo -n "请选择 [0-5]: "
    read -r choice

    case "$choice" in
        0) setup_preset "economic" ;;
        1) setup_preset "balanced" ;;
        2) setup_preset "quality" ;;
        3) setup_inherit ;;
        4)
            echo ""
            echo -e "支持: 标准 ID (${YELLOW}deepseek-v4-pro${NC}), 简写 (${YELLOW}deepseek${NC}), IDE 显示名 (${YELLOW}deepseek v4 pro${NC})"
            echo -n "模型名称: "
            read -r model
            setup_custom "$model"
            ;;
        5)
            if [[ -f "$USER_MODELS_FILE" ]]; then
                local user_preset
                user_preset=$("$PYTHON_CMD" -c "
import json
try:
    with open('$USER_MODELS_FILE') as f:
        data = json.load(f)
    print(data.get('_meta', {}).get('based_on', 'balanced'))
except:
    print('balanced')
" 2>/dev/null)
                setup_preset "$user_preset"
                _apply_user_overrides
            else
                setup_user edit
                print_info "请编辑 $USER_MODELS_FILE 后重新运行 setup.sh agent user"
            fi
            ;;
        *) print_error "无效选择" ;;
    esac
}
