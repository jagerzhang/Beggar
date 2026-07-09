---
name: beggar-notify
description: 群机器人通知调度。Leader 在关键节点通过 `beggar notify` 发送企业微信/飞书群消息。
---

# 群机器人通知调度

## 概述

此 Skill 为 beggar-workflow 提供群机器人 webhook 渠道通知。
支持企业微信群机器人和飞书群机器人两种渠道，通过 notify.py 直接调用 webhook API。

## 调用方式

Leader 通过 `beggar notify` 命令发送通知（自动处理全局/项目配置读取）：

```bash
beggar notify "<message>"
```

## 渠道

支持两种通知渠道，在 notify.json 中配置：

- **wecom** — 企业微信群机器人 webhook（发送 markdown 消息）
- **feishu** — 飞书群机器人 webhook（发送 text 消息）

## 通知调度规则

1. 检查 events.Nx.enabled 开关
2. 调用: `beggar notify "<message>"`
3. `beggar notify` 内部自动按优先级读取 notify.json（项目 > 全局）并发送

## 超时

默认 5 秒超时，超时后静默失败（不阻塞主流程）。

## 配置

通知配置存储在 `.codebuddy/notify.json`（项目级）或 `~/.codebuddy/notify.json`（全局级）：

```json
{
  "enabled": true,
  "channel": "wecom",
  "webhook_url": "https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=xxx",
  "events": {
    "N1": {"enabled": true},
    "N2": {"enabled": true}
  }
}
```

通过 `beggar quickstart` 或 `beggar setup notify` 交互式配置。
