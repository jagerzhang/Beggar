#!/bin/bash
# beggar colors/printing utilities

# ─── ANSI 颜色码降级（Windows 非 Git Bash 终端 / 管道重定向）────────────
_beggar_colors_enabled() {
    # 管道或文件重定向时禁用颜色
    [[ ! -t 1 ]] && return 1
    # Windows Git Bash/MSYS2 支持 ANSI，放行
    [[ -n "${MSYSTEM:-}" ]] && return 0
    # Linux/macOS 终端支持 ANSI
    case "$(uname -s 2>/dev/null)" in
        Linux|Darwin) return 0 ;;
    esac
    # 其他环境（原生 cmd.exe 等）禁用
    return 1
}

if _beggar_colors_enabled; then
    RED=$'\033[0;31m'
    GREEN=$'\033[0;32m'
    YELLOW=$'\033[1;33m'
    CYAN=$'\033[0;36m'
    NC=$'\033[0m'
else
    RED=""
    GREEN=""
    YELLOW=""
    CYAN=""
    NC=""
fi

print_header() {
    echo -e "${CYAN}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  Beggar · 赛博乞丐 | CodeBuddy 多 Agent 省钱开发方案 ║${NC}"
    echo -e "${CYAN}╠══════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║  - 项目源码: https://github.com/jagerzhang/beggar    ║${NC}"
    echo -e "${CYAN}║  - 项目作者: 江湖人称假哥                            ║${NC}"
    echo -e "${CYAN}║  - 开源协议: MIT License                             ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_success() { echo -e "${GREEN}[✓]${NC} $1"; }
print_info() { echo -e "${CYAN}[i]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1"; }
