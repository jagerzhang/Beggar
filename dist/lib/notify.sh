#!/bin/bash
# Beggar notification module
#
# Provides:
#   _dispatch_notify()   - send a notification message via notify.py
#   _configure_notify()  - interactive notification configuration wizard
#
# Dependencies (sourced by caller):
#   colors.sh     - print_* helpers
#   CODEBUDDY_DIR - target .codebuddy directory
#   BEGGAR_GLOBAL - "1" for global install
#   PROJECT_DIR   - project root directory
#
# Python 子进程通过环境变量传参，禁止 shell 字符串插值

# ─── Notification dispatch ──────────────────────────────────────────────
# 原 setup.sh L68-110

_dispatch_notify() {
    local msg="${1:-}"
    if [[ -z "$msg" ]]; then
        print_error "用法: _dispatch_notify <消息内容>"
        return 1
    fi

    # Find notify.py with fallback chain: project → global
    local notify_py=""
    if [[ -n "${CODEBUDDY_DIR:-}" && -f "$CODEBUDDY_DIR/skills/beggar-notify/notify.py" ]]; then
        notify_py="$CODEBUDDY_DIR/skills/beggar-notify/notify.py"
    fi
    if [[ -z "$notify_py" && -f "$HOME/.codebuddy/skills/beggar-notify/notify.py" ]]; then
        notify_py="$HOME/.codebuddy/skills/beggar-notify/notify.py"
    fi

    if [[ ! -f "$notify_py" ]]; then
        print_error "notify.py 未找到: $notify_py"
        return 1
    fi

    # 使用环境变量传参，避免 shell 字符串插值
    NOTIFY_MSG="$msg" NOTIFY_PY="$notify_py" "${PYTHON_CMD:-python3}" -c "
import json, os, sys, subprocess
# Find notify.json: project > global
notify_file = None
for path in ['.codebuddy/notify.json', os.path.expanduser('~/.codebuddy/notify.json')]:
    if os.path.isfile(path):
        notify_file = path
        break
if not notify_file:
    print('ERROR: notify.json 未找到（项目 .codebuddy/ 和 ~/.codebuddy/ 都不存在）', file=sys.stderr)
    sys.exit(1)
with open(notify_file) as f:
    data = json.load(f)
channel = data.get('channel', 'wecom')
webhook_url = data.get('webhook_url', '')
if not webhook_url:
    print(f'ERROR: notify.json ({notify_file}) 中 webhook_url 未配置', file=sys.stderr)
    sys.exit(1)
env = os.environ.copy()
env['BEGGAR_NOTIFY_CHANNEL'] = channel
env['BEGGAR_NOTIFY_WEBHOOK'] = webhook_url
message = os.environ.get('NOTIFY_MSG', '').rstrip('\n')
notify_py_path = os.environ.get('NOTIFY_PY', '')
import shutil
py_cmd = shutil.which('python3') or shutil.which('python') or 'python3'
subprocess.run([py_cmd, notify_py_path, message], env=env)
" || true  # 通知发送失败不阻塞主流程
}

# ─── Notification configuration wizard ──────────────────────────────────
# 原 setup.sh L934-1055

_configure_notify() {
    echo ""
    local NOTIFY_FILE="${CODEBUDDY_DIR:-$HOME/.codebuddy}/notify.json"

    # ── Check for existing config ──
    local existing_channel=""
    local existing_webhook=""
    if [[ -f "$NOTIFY_FILE" ]]; then
        local has_config
        has_config=$(NOTIFY_FILE="$NOTIFY_FILE" "${PYTHON_CMD:-python3}" -c "
import json, os
try:
    with open(os.environ['NOTIFY_FILE']) as f:
        data = json.load(f)
    channel = data.get('channel', '')
    webhook = data.get('webhook_url', '')
    if channel and webhook:
        # Mask: show first 30 chars + last 8 chars
        masked = webhook[:30] + '****' + webhook[-8:] if len(webhook) > 38 else '****'
        print(f'{channel}|{masked}')
    else:
        print('')
except Exception:
    print('')
" 2>/dev/null)
        if [[ -n "$has_config" ]]; then
            existing_channel="${has_config%%|*}"
            existing_webhook="${has_config##*|}"
            print_info "检测到已有通知配置："
            echo -e "  渠道: ${CYAN}${existing_channel}${NC}"
            echo -e "  Webhook: ${CYAN}${existing_webhook}${NC}"
            echo ""
            echo -n "是否修改通知配置？(y/N，默认否): "
            local modify
            if ! read -r modify </dev/tty 2>/dev/null; then
                print_warning "无法读取终端输入，保留现有通知配置"
                return 0
            fi
            if [[ -z "$modify" || "$modify" =~ ^[Nn]$ ]]; then
                print_success "保留现有通知配置，跳过重设"
                return 0
            fi
            print_info "将重新配置通知..."
            echo ""
        fi
    fi

    # ── Ask whether to enable notifications ──
    local enable_notify
    echo -n "是否启用工作流消息通知？(y/N): "
    if ! read -r enable_notify </dev/tty 2>/dev/null; then
        print_warning "无法读取终端输入，跳过通知配置"
        return 0
    fi
    if [[ -z "$enable_notify" || "$enable_notify" =~ ^[Nn]$ ]]; then
        print_info "跳过通知配置"
        return 0
    fi

    # ── Select notification channel ──
    echo ""
    echo -e "选择通知渠道："
    echo "  1) 企业微信群机器人 (推荐)"
    echo "  2) 飞书群机器人"
    echo ""
    echo -n "请选择 (1/2，默认 1): "
    local channel_choice
    if ! read -r channel_choice </dev/tty 2>/dev/null; then
        print_warning "无法读取终端输入，跳过通知配置"
        return 0
    fi
    local notify_channel="wecom"
    if [[ "$channel_choice" == "2" ]]; then
        notify_channel="feishu"
    fi
    echo ""

    # ── Collect webhook URL ──
    if [[ "$notify_channel" == "wecom" ]]; then
        echo -e "提示：在企业微信群中添加「群机器人」，获取 Webhook 地址。"
        echo -e "格式：https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=xxxxxxxx"
    else
        echo -e "提示：在飞书群中添加「自定义机器人」，获取 Webhook 地址。"
        echo -e "格式：https://open.feishu.cn/open-apis/bot/v2/hook/xxxxxxxx"
    fi
    echo ""
    echo -n "请输入 Webhook 地址: "
    read -r webhook_url </dev/tty 2>/dev/null
    echo ""

    # ── Write notify.json (all values via env, no shell interpolation) ──
    print_info "正在写入通知配置..."

    NOTIFY_CHANNEL="$notify_channel" \
    NOTIFY_FILE="$NOTIFY_FILE" \
    NOTIFY_WEBHOOK="$webhook_url" \
    "${PYTHON_CMD:-python3}" -c "
import json, os, tempfile
notify = {
    '_comment': 'beggar 通知配置 — 群机器人 webhook 渠道',
    'enabled': True,
    'channel': os.environ.get('NOTIFY_CHANNEL', 'wecom'),
    'webhook_url': os.environ.get('NOTIFY_WEBHOOK', ''),
    'events': {
        'N1': {'enabled': True},
        'N2': {'enabled': True},
        'N3': {'enabled': True},
        'N4': {'enabled': True},
        'N5': {'enabled': True},
        'N6': {'enabled': True},
        'N7': {'enabled': True},
        'N8': {'enabled': True},
        'N9': {'enabled': True}
    }
}
notify_file = os.environ['NOTIFY_FILE']
dir_name = os.path.dirname(notify_file)
tmp = tempfile.NamedTemporaryFile(mode='w', dir=dir_name,
                                  prefix='.', suffix='.tmp', delete=False)
try:
    json.dump(notify, tmp, indent=2, ensure_ascii=False)
    tmp.flush()
    os.fsync(tmp.fileno())
finally:
    tmp.close()
os.replace(tmp.name, notify_file)
"

    chmod 600 "$NOTIFY_FILE"
    print_success "通知配置文件已保护 (chmod 600)"

    # ── Update .gitignore ──
    if [[ "${BEGGAR_GLOBAL:-0}" != "1" ]]; then
        local gitignore_file="${PROJECT_DIR:-$(pwd)}/.gitignore"
        if [[ -f "$gitignore_file" ]]; then
            if ! grep -q "\.codebuddy/notify\.json" "$gitignore_file" 2>/dev/null; then
                echo "" >> "$gitignore_file"
                echo "# beggar 通知配置" >> "$gitignore_file"
                echo ".codebuddy/notify.json" >> "$gitignore_file"
                print_success "已更新 .gitignore，notify.json 已加入忽略列表"
            fi
        fi
    fi

    echo ""
    print_success "配置完成。Webhook 地址已保存到 notify.json，此文件已加入 .gitignore"
}