# 模型选择依据与 Benchmark 数据

> 本文档记录 Beggar 三档预设方案中每个模型选择的 Benchmark 数据依据。
> 数据来源：官方技术报告、swebench.com、独立评测（thesys.dev、coderouter.io、particula.tech、sotasync.com）
> 最后更新：2026-07-09

> **⚠️ 公网版说明**：Beggar 公网版仅支持 CodeBuddy 国内个人体验版可用的模型（DeepSeek/GLM/Kimi/MiniMax/Hy3 系列）。不支持 Claude/GPT/Gemini/Hunyuan-2.0-Thinking。模型可用性参考 CodeBuddy 各版本模型支持矩阵。

---

## 一、核心 Benchmark 指标说明

| 指标 | 测试内容 | 为什么重要 |
|------|---------|-----------|
| **SWE-bench Verified** | 真实 GitHub Issue 修复率（500 个人工验证问题） | 最接近"模型能不能干真实编码活"的评测 |
| **SWE-bench Pro** | 731 个未公开真实 Issue（更难，防数据污染） | 衡量最难编码任务的上限 |
| **LiveCodeBench** | 编程竞赛通过率 | 衡量代码生成纯能力 |
| **Terminal-Bench 2.0/2.1** | 真实终端环境多步任务（读输出、处理错误、迭代） | 衡量 Agent 执行命令+分析结果能力 |
| **GPQA Diamond** | 研究生级别科学问答 | 衡量推理深度 |

---

## 二、公网版可用模型 Benchmark 数据矩阵

### 编码能力

| 模型 | 平台倍率 | SWE-bench Verified | SWE-bench Pro | LiveCodeBench |
|------|---------|-------------------|---------------|---------------|
| DeepSeek-V4-Pro | x0.13 | **80.6%** | 55.4% | **93.5%** |
| Kimi-K2.6 | x0.50 | 80.2% | **58.6%** | — |
| DeepSeek-V4-Flash | x0.05 | **79.0%** | — | 91.6% |
| GLM-5.1 | x0.90 | 78.9% | 58.4% | — |
| **Hy3** | **x0.00** | **78.0%** | **57.9%** | — |
| DeepSeek-V3.2 | x0.15 | ~66% | — | — |
| MiniMax-M2.7 | x0.19 | — | 56.2% | — |

### Agent/工具使用能力

| 模型 | 倍率 | Terminal-Bench | Agent Elo | 长会话稳定性 |
|------|------|--------------|-----------|------------|
| DeepSeek-V4-Pro | x0.13 | 67.9% (2.0) | 1554 | 1M context |
| Kimi-K2.6 | x0.50 | 66.7% (2.0) | 1484 | **13h/4000+调用** |
| MiniMax-M2.7 | x0.19 | 57.0% (2.0) | 1514 | — |
| DeepSeek-V4-Flash | x0.05 | 56.9% (2.0) | 1395 | 1M context |
| GLM-5.1 | x0.90 | ~55%+ (2.0) | 1535 | — |
| **Hy3** | **x0.00** | — | — | WorkBuddy 90%成功率, ClawEval 68.5 |

### 推理/知识能力

| 模型 | 倍率 | GPQA Diamond |
|------|------|-------------|
| DeepSeek-V4-Pro | x0.13 | 90.1% |
| DeepSeek-V4-Flash | x0.05 | 88.1% |
| **Hy3** | **x0.00** | **90.4%** |

---

## 三、各 Agent 角色选型依据

### Leader（主面板，开发者自选）

| 推荐模型 | 倍率 | 选择依据 |
|---------|------|---------|
| deepseek-v4-pro | x0.13 | Agent Elo **1554**（最高）, Terminal-Bench **67.9%**, SWE-bench **80.6%**, 1M context, **48%降价后性价比极高** |
| glm-5.1 | x0.90 | Agent Elo 1535, SWE-bench 78.9%, 编码/推理/Agent 能力均衡 |
| kimi-k2.6 | x0.50 | Agent Elo 1484, 长会话稳定性极佳（13h/4000+调用不降级） |

### architect（方案设计）

需求：深度推理 + 系统思维 + 代码理解能力

| 预设 | 模型 | 依据 |
|------|------|------|
| Economic | **deepseek-v4-pro (x0.13)** | SWE-bench **80.6%** 代码理解力对方案设计至关重要。architect 是方向决策者，不能比 coder-senior 弱 |
| Balanced | **glm-5.1 (x0.90)** | Agent Elo 1535, SWE-bench 78.9%, 编码/推理/Agent 能力均衡。architect 是方向决策者，推理深度影响全链路。与 DeepSeek 形成跨厂商审查 |
| Quality | **glm-5.1 (x0.90)** | 公网版无 Claude Opus，GLM-5.1 是公网版最强可用推理模型 |

**为什么 architect 用 GLM-5.1 而非 V4-Pro？**
- 厂商多样性：Balanced 模式 coder-senior/standard/reviewer 已全是 DeepSeek 系，architect 保留 GLM 避免全系 DeepSeek
- architect 是方向决策者，需要不同厂商的推理视角
- GLM-5.1 Agent Elo 1535 接近 V4-Pro 的 1554，但提供了独立的推理视角

### coder-senior（复杂代码）

需求：最强代码生成 + 架构理解

| 预设 | 模型 | 依据 |
|------|------|------|
| Economic | deepseek-v4-pro (x0.13) | SWE-bench **80.6%**, LiveCodeBench **93.5%** 全场最高, Agent Elo 1554 |
| Balanced | deepseek-v4-pro (x0.13) | 同上。比 GLM-5.1 (x0.90) 便宜 86% 且 Agent Elo 更高 (1554 vs 1535) |
| Quality | deepseek-v4-pro (x0.13) | 公网版无 Claude Sonnet，V4-Pro 是最强可用编码模型 |

### coder-standard（常规代码）

需求：代码生成 + 性价比（25% 最高 token 消耗角色）

| 预设 | 模型 | 依据 |
|------|------|------|
| Economic | deepseek-v4-flash (x0.05) | SWE-bench **79.0%**（比 V3.2 的 ~66% 跳升 13 点）, LiveCodeBench 91.6%, **极低价格强模型** |
| Balanced | deepseek-v4-flash (x0.05) | 同上。25% 最高消耗角色必须极致性价比 |
| Quality | deepseek-v4-pro (x0.13) | SWE-bench 80.6%, 质量模式 standard 也用强模型 |

### coder-lite（简单代码）

需求：模式复制 + 最低成本（升级兜底）

| 预设 | 模型 | 依据 |
|------|------|------|
| Economic | hy3 (x0.00) | SWE-bench 78%+ClawEval 68.5，免费模型中编码能力最强 |
| Balanced | hy3 (x0.00) | 同上。即使偶尔升级到 standard (x0.05)，有效成本仍极低 |
| Quality | deepseek-v4-flash (x0.05) | SWE-bench 79%，质量模式不希望 lite 频繁升级 |

**成本梯度规则：senior > standard > lite**
- Economic: x0.13 > x0.05 > x0.00 ✓
- Balanced: x0.13 > x0.05 > x0.00 ✓
- Quality: x0.13 > x0.13 > x0.05 ✓

### reviewer（代码审查）

需求：代码理解 + 推理（找 bug、验规范）

| 预设 | 模型 | 依据 |
|------|------|------|
| Economic | hy3 (x0.00) | SWE-bench 78%代码理解+GPQA 90.4%推理，经济模式审查够用 |
| Balanced | **deepseek-v4-pro (x0.13)** | SWE-bench **80.6%** 代码理解强, GPQA **90.1%** 推理强 |
| Quality | **kimi-k2.6 (x0.50)** | **跨厂商审查**：coder 用 DeepSeek(V4-Pro)，reviewer 用 Kimi 提供第三方视角。长会话稳定性极佳 |

**Balanced 为什么 reviewer 用 V4-Pro？**
- 代码理解力 SWE-bench 80.6% 是公网版最强之一
- V4-Pro 降价后 x0.13，性价比极高
- 厂商多样性通过 Kimi (tester) 保证

**Quality 为什么 reviewer 用 Kimi 而非 V4-Pro？**
- Quality 模式 coder 全用 DeepSeek 系
- 如果 reviewer 也用 DeepSeek，会形成同系审查盲区
- Kimi 作为第三方厂商提供独立的审查视角
- Kimi 实测 13h/4000+ 调用不降级，长会话审查稳定可靠

### tester（测试验证）

需求：执行命令 + 分析结果 + 工具调用

| 预设 | 模型 | 依据 |
|------|------|------|
| Economic | hy3 (x0.00) | WorkBuddy任务成功率90%+ClawEval 68.5，Agent能力强 |
| Balanced | **kimi-k2.6 (x0.50)** | Agent能力+长上下文+长会话稳定性。13h/4000+调用不降级 |
| Quality | **kimi-k2.6 (x0.50)** | 同 Balanced。公网版无 Gemini 3.5 Flash，K2.6 是 Agent 能力最强的可用替代 |

**Balanced 为什么 tester 用 Kimi 而非 V4-Pro？**
- **厂商多样性**：Balanced 模式 coder-senior/standard/reviewer 已全是 DeepSeek 系，tester 保留 Kimi 避免全系 DeepSeek
- Kimi 长会话稳定性极佳（13h/4000+调用不降级）
- Kimi Terminal-Bench 66.7% 接近 V4-Pro 的 67.9%

### recorder（知识沉淀）

需求：理解和总结能力（最低优先级）

| 预设 | 模型 | 依据 |
|------|------|------|
| Economic | hy3 (x0.00) | SWE-bench 78%+reasoning，5% 最低 token 占比 |
| Balanced | hy3 (x0.00) | 同上，不值得在最低优先级角色花钱 |
| Quality | hy3 (x0.00) | 公网版无 Claude Haiku，hy3 免费且推理能力够用 |

### goal-evaluator（独立判定）

需求：轻量推理 + 与 Leader 不同厂商（避免自判偏差）

| 预设 | 模型 | 依据 |
|------|------|------|
| Economic | kimi-k2.5 (x0.00) | 免费模型，与 Leader 模型不同厂商 |
| Balanced | kimi-k2.5 (x0.00) | 免费模型，与 Leader (V4-Pro) 不同厂商 |
| Quality | kimi-k2.5 (x0.00) | 免费模型，与 Leader (V4-Pro) 不同厂商 |

### director（最终裁决）

需求：最强推理 + 根因分析能力

| 预设 | 模型 | 依据 |
|------|------|------|
| Economic | glm-5.1 (x0.90) | 公网版最强可用推理模型 |
| Balanced | glm-5.1 (x0.90) | 同上。Director 仅在 3 轮全败时激活 1 次，token 消耗可控 |
| Quality | glm-5.1 (x0.90) | 公网版无 Claude Opus，GLM-5.1 是最强替代 |

---

## GLM-5v-Turbo（多模态视觉编程）

> **定位**：原生多模态 Coding 基座，从预训练阶段融合视觉与文本。

**在 Beggar 工作流中的适用场景**

| 场景 | 适用度 | 说明 |
|------|--------|------|
| UI/前端开发（设计稿→代码）| ⭐⭐⭐⭐⭐ | Design2Code 94.8% 全场最高 |
| 截图分析 / Bug 复现 | ⭐⭐⭐⭐ | 原生视觉理解，无需额外 OCR |
| Web 开发（HTML/CSS 为主）| ⭐⭐⭐⭐ | Vision2Web + BrowseComp-VL 双强 |
| 后端逻辑代码 | ⭐⭐⭐ | 纯文本能力持平 GLM-5-Turbo，但不如纯文本模型划算 |

> **结论：GLM-5v-Turbo 不适合作为预设中的通用 agent 模型，但在需要视觉输入的前端/UI 任务中是当前最佳选择。** 建议作为 `agent custom` 的可选模型。价格 x0.81 比 GLM-5.1(x0.90) 还便宜，视觉能力是白送的增值。

---

## 四、厂商多样性分析

### 经济模式

| 厂商 | 覆盖角色 | 倍率 |
|------|---------|------|
| DeepSeek | architect, coder-senior, coder-standard | x0.05~x0.13 |
| Hy3 | coder-lite, reviewer, tester, recorder | x0.00 |
| Kimi | reviewer-b, goal-evaluator | x0.00 |
| GLM | director | x0.90 |

> DeepSeek 承担架构设计+代码生成，Hy3 承担审查+测试+归档，Kimi 提供辅审+目标验证。成本 x0.05，仍极低。

### 平衡模式

| 厂商 | 覆盖角色 | 倍率 |
|------|---------|------|
| Z.AI (GLM) | architect, director | x0.90 |
| DeepSeek | coder-senior, coder-standard, reviewer | x0.05~x0.13 |
| Hy3 | coder-lite, recorder | x0.00 |
| Kimi | reviewer-b, tester, goal-evaluator | x0.00~x0.50 |

> **四厂商覆盖**：GLM-5.1 负责架构设计+裁决，DeepSeek 负责代码生成+主审，Kimi 负责辅审+测试，Hy3 负责简单代码+归档。architect 与 reviewer 不同厂商，形成跨厂商审查。成本 x0.29。

### 质量模式

| 厂商 | 覆盖角色 | 倍率 |
|------|---------|------|
| Z.AI (GLM) | architect, director | x0.90 |
| DeepSeek | coder-senior, coder-standard, coder-lite, reviewer-b | x0.05~x0.13 |
| Kimi | reviewer, tester, goal-evaluator | x0.00~x0.50 |
| Hy3 | recorder | x0.00 |

> 公网版无 Claude/GPT/Gemini，质量模式通过 GLM+DeepSeek+Kimi 三厂商组合最大化质量。DeepSeek V4-Pro 全线代码 + Kimi 主审交叉验证 + GLM 架构裁决。

---

## 五、模型选择铁律

1. **成本梯度不可倒挂**：senior > standard > lite（任何预设）
2. **角色匹配优先于厂商偏好**：选对能力 > 选便宜的
3. **审查与编码不同厂商**：减少"自己写自己审"的同系盲区
4. **免费模型物尽其用**：hy3 SWE-bench 78%+GPQA 90.4%+ClawEval 68.5，免费模型中综合最强；kimi-k2.5 免费提供独立判定
5. **数据说话**：选型必须有 Benchmark 支撑，禁止"感觉这个模型好"
6. **公网版约束**：仅使用 CodeBuddy 国内个人体验版可用的模型，不支持 Claude/GPT/Gemini

---

## 六、数据来源

| 来源 | URL | 数据类型 |
|------|-----|---------|
| SWE-bench 官方 | swebench.com | Verified / Pro 排行榜 |
| DeepSeek V4 技术报告 | Hugging Face model card (2026-04-24) | 官方 Benchmark |
| 腾讯混元官方 | 腾讯云 TokenHub / Hy3 正式发布 (2026-07-06) | Hy3 正式版 Benchmark (SWE-bench 78%、GPQA 90.4%、ClawEval 68.5) |
| thesys.dev | thesys.dev/blogs/deepseek-v4-pro | 独立对比评测 |
| coderouter.io | coderouter.io/blog/deepseek-v4-pro-vs-v4-flash-coding | 独立编码评测 |
| particula.tech | particula.tech/blog/deepseek-v4-vs-kimi-k2-6-vs-glm-5-1 | 开源模型横评 |
| sotasync.com | sotasync.com/reader/2026-04-30-kimi-k2-vs-glm-5 | 国产模型编程对决 |
| emergentmind.com | emergentmind.com/topics/glm-5v-turbo | GLM-5v-Turbo 技术解析 |
| CodeSOTA | codesota.com/llm/coding-benchmarks | 编码 Benchmark 汇总 |
