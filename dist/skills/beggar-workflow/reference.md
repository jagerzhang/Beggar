# 参考信息（非流程必需，按需查阅）

> 本文件包含 beggar 的配置参考信息，不参与流程执行，仅在需要时查阅。

## 费用估算

| 预设 | 加权单价 | +RTK 压缩后 | vs 全 Opus |
|------|---------|-------------|-----------|
| economic | x0.06 | ~x0.06 | 节省 94% |
| balanced | x0.12 | ~x0.15 | 节省 91% |
| quality | x1.05 | ~x0.80 | 节省 56% |

**经济模式下一个完整开发流程的典型成本**：
- 主会话 (DeepSeek V4-Pro, 30% token): 0.13 × 0.30 = 0.039
- Coder 加权 (40% token): ~0.04 (大部分任务走 lite/standard/V4-Flash)
- Reviewer (15% token): 0.00 × 0.15 = 0.00 (免费)
- Tester (10% token): 0.00 × 0.10 = 0.00 (免费)
- Recorder (5% token): 0.00 × 0.05 = 0.00 (免费)
- **总加权: ~x0.03**

## RTK 集成（可选）

- 通过 `.codebuddy/hooks/beggar-notify-hook.py` 自动注册 RTK hook
- 每次发往模型的请求终端输出会被 RTK 压缩
- 成本进一步降低 60-90%（终端输出不计模型 token，但会影响传输成本和延时）
- `beggar stats` 可查看 RTK 压缩收益

## 模型预设切换

```bash
# 简单需求（省钱优先）
.codebuddy/setup.sh agent preset economic

# 中等需求（默认推荐）
.codebuddy/setup.sh agent preset balanced

# 复杂/高风险需求（质量优先）
.codebuddy/setup.sh agent preset quality
```

预设切换即时生效，无需重新 init。
