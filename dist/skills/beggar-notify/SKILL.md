---
name: beggar-notify
description: 飞鸽传书通知调度。Leader 在关键节点通过 `beggar notify` 发送客服号-markdown 通知。
---

# 飞鸽传书通知调度

## 概述

此 Skill 为 beggar-workflow 提供客服号-markdown 渠道通知。
通过 curl 直调飞鸽传书 HTTP endpoint，不依赖 CodeBuddy MCP 集成。

## 调用方式

Leader 通过 `beggar notify` 命令发送通知（自动处理全局/项目令牌读取）：

```bash
beggar notify "<message>"
```

## 渠道

统一使用客服号-markdown 渠道（`send_wecom_cs_markdown`），不再支持语音和邮件渠道。

## 通知调度规则

1. 检查 events.Nx.enabled 开关
2. 调用: `beggar notify "<message>"`
3. `beggar notify` 内部自动按优先级读取 notify.json（项目 > 全局）并发送

## 超时

notify.py 内设 `urllib.request` 5 秒超时，防止 hang 住主流程。

## 配置

通知令牌存储在 `notify.json` 中，**读取优先级**：

1. `.codebuddy/notify.json` — 项目级（覆盖全局）
2. `~/.codebuddy/notify.json` — 全局（所有项目共享）
3. 两者都不存在 → 跳过通知

Leader 读取时按此顺序查找，找到第一个 `enabled: true` 的配置即停止。

## 安全

- Token 通过环境变量 `BEGGAR_NOTIFY_TOKEN` 传入，不会在 `ps` 中泄露
- notify.json 存储令牌，已加入 `.gitignore`
- `.codebuddy/notify.json` 和 `~/.codebuddy/notify.json` 权限 `chmod 600`，仅 owner 可读
- 消息内容由 Leader 预构造固定模板，不含用户输入
