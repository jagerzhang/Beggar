#!/bin/bash
# beggar-notify — 环境变量加载脚本
# 用法: eval $(bash .codebuddy/skills/beggar-notify/load-env.sh)
# 输出可直接 eval 的 export 语句，将 notify.json 中的配置加载到当前 shell

set -e

# 定位 notify.json（项目级 > 全局 ~/.codebuddy/ > CWD）
NOTIFY_FILE=""
if [[ -f ".codebuddy/notify.json" ]]; then
    NOTIFY_FILE=".codebuddy/notify.json"
elif [[ -f "$HOME/.codebuddy/notify.json" ]; then
    NOTIFY_FILE="$HOME/.codebuddy/notify.json"
elif [[ -f "notify.json" ]]; then
    NOTIFY_FILE="notify.json"
else
    # 静默退出，不输出任何内容
    exit 0
fi

python3 -c "
import json, sys, os

try:
    with open('$NOTIFY_FILE') as f:
        data = json.load(f)
    
    token = data.get('token', '')
    sendto = data.get('sendTo', '')
    
    if token and sendto:
        print(f'export BEGGAR_NOTIFY_TOKEN={json.dumps(token)}')
        print(f'export BEGGAR_NOTIFY_SENDTO={json.dumps(sendto)}')
        print(f'export BEGGAR_NOTIFY_ENABLED=1')
except Exception:
    # 任何解析错误都静默忽略，不破坏主流程
    sys.exit(0)
"
