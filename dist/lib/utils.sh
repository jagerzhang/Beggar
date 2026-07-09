#!/bin/bash
# beggar utilities

# ─── Windows / MSYS2 兼容检测 ────────────────────────────────────────────
# 检测当前是否运行在 Windows Git Bash / MSYS2 环境下
_is_windows() {
    [[ -n "${MSYSTEM:-}" ]] && return 0
    case "$(uname -s 2>/dev/null)" in
        MINGW*|MSYS*|CYGWIN*) return 0 ;;
    esac
    return 1
}

# 创建临时目录，Windows 下自动转换路径格式供原生程序使用
_mktemp_dir() {
    local tmp
    tmp=$(mktemp -d 2>/dev/null || mktemp -d -t beggar)
    if _is_windows && command -v cygpath &>/dev/null; then
        tmp=$(cygpath -m "$tmp")
    fi
    echo "$tmp"
}

# 跨平台 sed 原地编辑（macOS 需要 -i ''，Linux/Git Bash 用 -i）
_sed_inplace() {
    local pattern="$1"
    local file="$2"
    case "$(uname -s 2>/dev/null)" in
        Darwin) sed -i '' "$pattern" "$file" ;;
        *)      sed -i  "$pattern" "$file" ;;
    esac
}

# 检测 Python 可执行命令（Windows 上通常为 python 而非 python3）
_resolve_python() {
    if [[ -n "${PYTHON_CMD:-}" ]] && command -v "$PYTHON_CMD" &>/dev/null; then
        echo "$PYTHON_CMD"
        return
    fi
    if command -v python3 &>/dev/null; then
        echo "python3"
    elif command -v python &>/dev/null; then
        echo "python"
    else
        echo "python3"  # fallback，让后续报错自然产生
    fi
}

# 将文件路径追加到 .beggar-checksums 清单（供卸载时按清单精确删除）
# 用法: _record_manifest "persona-active.json"
_record_manifest() {
    local checksums_file="${CODEBUDDY_DIR:-$HOME/.codebuddy}/.beggar-checksums"
    if [[ -f "$checksums_file" ]]; then
        _sed_inplace "/^file:$1 /d" "$checksums_file" 2>/dev/null || true
        echo "file:$1 INSTALLED" >> "$checksums_file"
    fi
}

# 判断文件是否为 openspec 相关业务文件（不进入 beggar 管理清单）
# 用法: _is_biz_only_on_missing <rel_path>  →  返回 0=true, 1=false
_is_biz_only_on_missing() {
    local rel_path="$1"
    local biz_paths=(
        "commands/opsx"
        "skills/openspec-apply-change"
        "skills/openspec-archive-change"
        "skills/openspec-explore"
        "skills/openspec-propose"
    )
    for prefix in "${biz_paths[@]}"; do
        if [[ "$rel_path" == "$prefix" || "$rel_path" == "$prefix"/* ]]; then
            return 0
        fi
    done
    return 1
}

# ─── 旧版 models.json 格式检测 ──────────────────────────────────────────
# 检测文件是否为 beggar 格式（包含 presets 或 aliases 键）
# 用于区分 beggar 旧版 models.json 和 CodeBuddy 官方 models.json
# 用法: _is_beggar_models_json <file_path>  →  返回 0=true, 1=false
_is_beggar_models_json() {
    [[ -z "${1:-}" || ! -f "$1" ]] && return 1
    # beggar 的 models.json 包含 "presets" 或 "aliases" 顶层键
    # CodeBuddy 官方 models.json 不含这些键，用 grep 检测避免 Python 引号嵌套问题
    grep -qE '"(presets|aliases)"[[:space:]]*:' "$1" 2>/dev/null
}

_global_has_beggar_hooks() {
    local global_settings="${GLOBAL_SETTINGS:-$HOME/.codebuddy/settings.json}"
    if [[ ! -f "$global_settings" ]]; then
        return 1
    fi
    GLOBAL_SETTINGS="$global_settings" "${PYTHON_CMD:-python3}" -c "
import json, sys, os
try:
    with open(os.environ.get('GLOBAL_SETTINGS', '')) as f:
        data = json.load(f)
    hooks = data.get('hooks', {})
    for event_name, matchers in hooks.items():
        for matcher in (matchers if isinstance(matchers, list) else []):
            for hook in matcher.get('hooks', []):
                if 'beggar-notify-hook.py' in hook.get('command', ''):
                    print('true')
                    sys.exit(0)
    print('false')
except Exception:
    print('false')
" 2>/dev/null
}