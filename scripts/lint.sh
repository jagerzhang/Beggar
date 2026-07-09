#!/bin/bash
# ShellCheck 静态分析脚本
# 用法: bash scripts/lint.sh
# 需要安装 shellcheck: brew install shellcheck (macOS) 或 apt install shellcheck (Linux)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# 检查 shellcheck 是否安装
if ! command -v shellcheck &>/dev/null; then
    echo "ERROR: shellcheck 未安装"
    echo "  macOS:  brew install shellcheck"
    echo "  Linux:  apt install shellcheck"
    echo "  详见:   https://github.com/koalaman/shellcheck#installing"
    exit 1
fi

echo "Running shellcheck on all shell scripts..."
echo ""

# 收集所有需要检查的 shell 脚本
SHELL_SCRIPTS=(
    "$PROJECT_DIR/install.sh"
    "$PROJECT_DIR/dist/setup.sh"
)

# 添加 dist/lib/ 下的所有 .sh 文件
while IFS= read -r -d '' f; do
    SHELL_SCRIPTS+=("$f")
done < <(find "$PROJECT_DIR/dist/lib" -name "*.sh" -print0 2>/dev/null)

# 添加 dist/skills/ 下的 shell 脚本
while IFS= read -r -d '' f; do
    SHELL_SCRIPTS+=("$f")
done < <(find "$PROJECT_DIR/dist/skills" -name "*.sh" -print0 2>/dev/null)

# 添加 scripts/ 下的 shell 脚本
if [[ -d "$PROJECT_DIR/scripts" ]]; then
    while IFS= read -r -d '' f; do
        SHELL_SCRIPTS+=("$f")
    done < <(find "$PROJECT_DIR/scripts" -name "*.sh" -print0 2>/dev/null)
fi

ERRORS=0
TOTAL=${#SHELL_SCRIPTS[@]}

for script in "${SHELL_SCRIPTS[@]}"; do
    if [[ -f "$script" ]]; then
        if shellcheck -x "$script"; then
            echo "  ✓ $(basename "$script")"
        else
            echo "  ✗ $(basename "$script")"
            ERRORS=$((ERRORS + 1))
        fi
    fi
done

echo ""
echo "Checked $TOTAL scripts, $ERRORS with errors."

if [[ $ERRORS -gt 0 ]]; then
    exit 1
fi
