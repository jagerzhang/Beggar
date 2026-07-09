#!/bin/bash
# beggar platform detection utilities

# 检测操作系统类型
detect_os() {
    case "$(uname -s 2>/dev/null)" in
        Darwin)             echo "macos" ;;
        Linux)              echo "linux" ;;
        MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
        *)                  echo "unknown" ;;
    esac
}

detect_platform() {
    if [[ -n "${VSCODE_PID:-}" ]] || [[ -n "${CODEBUDDY_IDE:-}" ]] || [[ -n "${TERM_PROGRAM:-}" && "${TERM_PROGRAM}" == "vscode" ]]; then
        echo "ide"
    else
        echo "cli"
    fi
}

check_model_platform() {
    local model="$1"
    local current_platform="$2"

    if [[ "$model" == "inherit" ]]; then
        return 0
    fi

    MODEL_ID="$model" PLATFORM="$current_platform" "$PYTHON_CMD" -c "
import json, sys, os
model_id = os.environ.get('MODEL_ID', '')
platform = os.environ.get('PLATFORM', '')
with open(os.environ.get('MODELS_FILE', '')) as f:
    data = json.load(f)
for section in ['paid', 'free']:
    items = data['models'].get(section, {})
    if isinstance(items, list):
        for m in items:
            if m['id'] == model_id:
                if platform in m.get('platform', ['cli', 'ide']):
                    sys.exit(0)
                else:
                    sys.exit(1)
    elif isinstance(items, dict):
        for family_models in items.values():
            if isinstance(family_models, list):
                for m in family_models:
                    if m['id'] == model_id:
                        if platform in m.get('platform', ['cli', 'ide']):
                            sys.exit(0)
                        else:
                            sys.exit(1)
sys.exit(0)
" 2>/dev/null
}
