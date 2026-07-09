#!/usr/bin/env python3
"""Beggar 通知发送 — 通过企业微信群机器人或飞书群机器人发送消息

支持的通知渠道:
  - wecom: 企业微信群机器人 webhook (https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=xxx)
  - feishu: 飞书群机器人 webhook (https://open.feishu.cn/open-apis/bot/v2/hook/xxx)

用法:
  通过 notify.json 配置渠道和 webhook URL:
  {
    "enabled": true,
    "channel": "wecom",          # 或 "feishu"
    "webhook_url": "https://...",  # 群机器人 webhook 地址
    "events": { ... }
  }

  或通过环境变量:
  BEGGAR_NOTIFY_CHANNEL=wecom BEGGAR_NOTIFY_WEBHOOK="https://..." notify.py "<message>"

返回: 0=成功, 非0=失败
"""
import sys, os, json, urllib.request, urllib.error

WECOM_API = "https://qyapi.weixin.qq.com/cgi-bin/webhook/send"
FEISHU_API = "https://open.feishu.cn/open-apis/bot/v2/hook/"
TIMEOUT = 5


def send_wecom(webhook_url, message):
    """通过企业微信群机器人发送 markdown 消息"""
    # 如果传入的是完整 URL（含 key 参数），直接使用
    if webhook_url.startswith(WECOM_API):
        url = webhook_url
    else:
        # 否则将 webhook_url 作为 key 拼接
        url = f"{WECOM_API}?key={webhook_url}"

    body = json.dumps({
        "msgtype": "markdown",
        "markdown": {"content": message},
    }, ensure_ascii=False).encode("utf-8")

    req = urllib.request.Request(
        url, data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    urllib.request.urlopen(req, timeout=TIMEOUT)


def send_feishu(webhook_url, message):
    """通过飞书群机器人发送 markdown 消息

    webhook_url 可以是完整地址，也可以是 token 部分。
    """
    if webhook_url.startswith(FEISHU_API):
        url = webhook_url
    else:
        url = f"{FEISHU_API}{webhook_url}"

    body = json.dumps({
        "msg_type": "text",
        "content": {"text": message},
    }, ensure_ascii=False).encode("utf-8")

    req = urllib.request.Request(
        url, data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    urllib.request.urlopen(req, timeout=TIMEOUT)


def main():
    # 优先从环境变量读取（_dispatch_notify 通过环境变量传参）
    channel = os.environ.get("BEGGAR_NOTIFY_CHANNEL", "")
    webhook_url = os.environ.get("BEGGAR_NOTIFY_WEBHOOK", "")
    message = sys.argv[1] if len(sys.argv) > 1 else ""

    # 如果环境变量未设置，尝试从 notify.json 读取
    if not channel or not webhook_url:
        notify_file = None
        for path in ['.codebuddy/notify.json', os.path.expanduser('~/.codebuddy/notify.json')]:
            if os.path.isfile(path):
                notify_file = path
                break
        if notify_file:
            try:
                with open(notify_file) as f:
                    data = json.load(f)
                channel = channel or data.get("channel", "wecom")
                webhook_url = webhook_url or data.get("webhook_url", "")
            except Exception:
                pass

    if not message:
        print('用法: BEGGAR_NOTIFY_CHANNEL=wecom BEGGAR_NOTIFY_WEBHOOK=xxx notify.py "<message>"', file=sys.stderr)
        sys.exit(1)
    if not webhook_url:
        print("ERROR: BEGGAR_NOTIFY_WEBHOOK 未设置（也未在 notify.json 中配置 webhook_url）", file=sys.stderr)
        sys.exit(1)

    channel = channel.lower()
    message = message.replace('\\n', '\n')

    try:
        if channel == "wecom":
            send_wecom(webhook_url, message)
        elif channel == "feishu":
            send_feishu(webhook_url, message)
        else:
            print(f"ERROR: 不支持的通知渠道 '{channel}'，支持: wecom, feishu", file=sys.stderr)
            sys.exit(1)
    except urllib.error.HTTPError as e:
        print(f"发送失败 (HTTP {e.code})", file=sys.stderr)
        sys.exit(e.code)
    except Exception as e:
        print(f"发送失败: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
