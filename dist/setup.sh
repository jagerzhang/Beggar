#!/bin/bash
# Beggar · 赛博乞丐 | CodeBuddy 多 Agent 省钱开发方案配置管理脚本
# 用法: .codebuddy/setup.sh [init|agent|show|help|...]

set -e

# ---- Python 命令检测（Windows 兼容：Windows 上通常为 python 而非 python3）----
export PYTHON_CMD="${PYTHON_CMD:-}"
if [[ -z "$PYTHON_CMD" ]]; then
    if command -v python3 &>/dev/null; then
        export PYTHON_CMD="python3"
    elif command -v python &>/dev/null; then
        export PYTHON_CMD="python"
    else
        export PYTHON_CMD="python3"
    fi
fi

# ---- 项目隔离模式检测 ---
if [[ "${1:-}" == "--global" || "${1:-}" == "-g" ]]; then
    shift
    CODEBUDDY_DIR="$HOME/.codebuddy"
    mkdir -p "$CODEBUDDY_DIR"
    PROJECT_DIR="$HOME"
    BEGGAR_GLOBAL="${BEGGAR_GLOBAL:-1}"
elif [[ "${1:-}" == "--project" || "${1:-}" == "-p" ]]; then
    shift
    CODEBUDDY_DIR="$(pwd)/.codebuddy"
    mkdir -p "$CODEBUDDY_DIR"
    PROJECT_DIR="$(pwd)"
    BEGGAR_PROJECT_MODE=1
else
    # 自动探测 beggar 操作目标
    _detect_beggar_target() {
        local dir
        dir="$(pwd)"
        while [[ "$dir" != "/" ]]; do
            if [[ -f "$dir/.codebuddy/setup.sh" ]]; then
                echo "$dir/.codebuddy"
                return 0
            fi
            dir="$(dirname "$dir")"
        done
        if [[ -f "$HOME/.codebuddy/setup.sh" ]]; then
            echo "$HOME/.codebuddy"
            return 0
        fi
        echo ""
    }

    if [[ "${BASH_SOURCE[0]}" == "$HOME/.codebuddy/setup.sh" ]] || \
       [[ "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" == "$HOME/.codebuddy" ]]; then
        CODEBUDDY_DIR="${BEGGAR_DIR:-$(_detect_beggar_target)}"
    else
        CODEBUDDY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    fi
    PROJECT_DIR="$(dirname "$CODEBUDDY_DIR")"
fi

AGENTS_DIR="$CODEBUDDY_DIR/agents"
MODELS_FILE="$CODEBUDDY_DIR/beggar-models.json"
USER_MODELS_FILE="$CODEBUDDY_DIR/user-models.json"
TOOLS_DIR="$CODEBUDDY_DIR/tools"
PERSONAS_FILE="$CODEBUDDY_DIR/personas.json"

export CODEBUDDY_DIR AGENTS_DIR MODELS_FILE USER_MODELS_FILE TOOLS_DIR PERSONAS_FILE PROJECT_DIR

# 项目隔离模式：全局文件作为 fallback
if [[ "$BEGGAR_PROJECT_MODE" == "1" ]]; then
    [[ -f "$MODELS_FILE" ]] || MODELS_FILE="$HOME/.codebuddy/beggar-models.json"
    [[ -f "$PERSONAS_FILE" ]] || PERSONAS_FILE="$HOME/.codebuddy/personas.json"
fi

# Agent 列表
AGENTS=(architect coder-senior coder-standard coder-lite reviewer tester recorder director)

# 全局安装模式检测
BEGGAR_GLOBAL="${BEGGAR_GLOBAL:-0}"
export BEGGAR_GLOBAL

# ---- 模块加载 ---
LIB_DIR="${BEGGAR_LIB_DIR:-$CODEBUDDY_DIR/lib}"
if [[ ! -d "$LIB_DIR" ]]; then
    LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/lib" 2>/dev/null && pwd)"
fi

if [[ ! -d "$LIB_DIR" ]]; then
    echo "ERROR: Cannot find beggar lib directory"
    echo "  Looked at: CODEBUDDY_DIR/lib ($CODEBUDDY_DIR/lib)"
    echo "  Looked at: script-relative lib ($(dirname "${BASH_SOURCE[0]}")/lib)"
    exit 1
fi

# Source modules in dependency order
source "$LIB_DIR/colors.sh"
source "$LIB_DIR/utils.sh"
source "$LIB_DIR/platform.sh"
source "$LIB_DIR/models.sh"
source "$LIB_DIR/preset.sh"
source "$LIB_DIR/rtk.sh"
source "$LIB_DIR/notify.sh"
source "$LIB_DIR/hooks.sh"
source "$LIB_DIR/persona.sh"
source "$LIB_DIR/shell.sh"
source "$LIB_DIR/init.sh"
source "$LIB_DIR/interactive.sh"
source "$LIB_DIR/validate.sh"
source "$LIB_DIR/update.sh"
source "$LIB_DIR/uninstall.sh"
source "$LIB_DIR/guard.sh"

# ---- 入口分发 ---
main() {
    case "${1:-help}" in
        init|setup)
            if [[ "${2:-}" == "shell" ]]; then
                _setup_shell_alias
            else
                do_init
            fi
            ;; 
        agent)   shift; setup_agent "$@" ;;
        show|status)         show_config ;;
        preset)  shift; setup_preset "$@" ;;
        persona) shift; do_persona "$@" ;;
        validate|check)      do_validate ;;
        update|upgrade)      do_update ;;
        reinstall)           do_reinstall ;;
        uninstall|remove)    do_uninstall ;;
        diff)    do_diff ;;
        stats)   do_stats ;;
        guard)   shift; setup_guard "$@" ;;
        notify)  shift; _dispatch_notify "$@" ;;
        quickstart|tour|wizard) PLATFORM="$(detect_platform)" exec "$PYTHON_CMD" "$LIB_DIR/quickstart.py" ;;
        help|--help|-h)      show_help ;;
        *)       show_help ;;
    esac
}

main "$@"
