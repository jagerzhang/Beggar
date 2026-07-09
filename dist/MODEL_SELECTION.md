# 模型选择依据与 Benchmark 数据

> 本文档记录 Beggar 三档预设方案中每个模型选择的 Benchmark 数据依据。
> 数据来源：官方技术报告、swebench.com、独立评测（thesys.dev、coderouter.io、particula.tech、sotasync.com）
> 最后更新：2026-07-09

> **⚠️ 公网版说明**：Beggar 公网版仅支持 CodeBuddy 国内个人体验版可用的模型（DeepSeek/GLM/Kimi/MiniMax/Hy3 系列）。不支持 Claude/GPT/Gemini。模型可用性与定价参考 CodeBuddy 各版本模型支持矩阵。Hy3 是公网版唯一免费模型。

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

## 二、公网版可用模型清单与定价

| 模型 | 模型 ID | 平台倍率 | tags | 平台 | 备注 |
|------|---------|---------|------|------|------|
| **GLM-5.2** | `glm-5.2` | **x0.79** | code, agent, reasoning, long-context | CLI/IDE | 开源最强文本模型 |
| GLM-5.1 | `glm-5.1` | x0.79 | code, agent | CLI/IDE | 同价但被5.2超越 |
| GLM-5.0 | `glm-5.0` | x0.80 | general | CLI/IDE | |
| GLM-5.0-Turbo | `glm-5.0-turbo` | x0.95 | general, fast | CLI/IDE | |
| GLM-5v-Turbo | `glm-5v-turbo` | x0.95 | multimodal, code | CLI/IDE | 多模态视觉编程 |
| GLM-4.7 | `glm-4.7` | x0.23 | general, fast | CLI/IDE | |
| MiniMax-M3 | `minimax-m3` | x0.25 | general, fast | CLI/IDE | 新版 |
| MiniMax-M2.7 | `minimax-m2.7` | x0.19 | general, fast | CLI/IDE | |
| **Kimi-K2.7-Code** | `kimi-k2.7` | **x0.57** | code, agent, tool-use | CLI/IDE | 编程专用强化 |
| Kimi-K2.6 | `kimi-k2.6` | x0.52 | agent, tool-use | CLI/IDE | 建议升级到K2.7 |
| Kimi-K2.5 | `kimi-k2.5` | x0.45 | general, agent | CLI/IDE | 已不再免费 |
| **DeepSeek-V4-Pro** | `deepseek-v4-pro` | **x0.16** | code, agent, reasoning | CLI/IDE | 性价比极高 |
| **DeepSeek-V4-Flash** | `deepseek-v4-flash` | **x0.06** | code, fast | CLI/IDE | 极低价格强模型 |
| DeepSeek-V3.2 | `deepseek-v3-2-volc` | x0.29 | general | CLI/IDE | 旧版 |
| **Hy3** | `hy3` | **x0.00** | general, agent, reasoning | CLI/IDE | 唯一免费模型 |

---

## 三、全模型 Benchmark 数据矩阵

### 编码能力

| 模型 | 平台倍率 | SWE-bench Verified | SWE-bench Pro | LiveCodeBench |
|------|---------|-------------------|---------------|---------------|
| GLM-5.2 | x0.79 | ~82% | **62.1%** | **93.5%** |
| DeepSeek-V4-Pro | x0.16 | **80.6%** | 55.4% | **93.5%** |
| Kimi-K2.6 | x0.52 | 80.2% | **58.6%** | — |
| DeepSeek-V4-Flash | x0.06 | **79.0%** | — | 91.6% |
| GLM-5.1 | x0.79 | 78.9% | 58.4% | — |
| **Hy3** | **x0.00** | **78.0%** | **57.9%** | — |
| DeepSeek-V3.2 | x0.29 | ~66% | — | — |
| MiniMax-M2.7 | x0.19 | — | 56.2% | — |

### Agent/工具使用能力

| 模型 | 倍率 | Terminal-Bench | Agent Elo | 长会话稳定性 |
|------|------|--------------|-----------|------------|
| GLM-5.2 | x0.79 | **81.0%** (2.1) | ~1580 | 1M context |
| DeepSeek-V4-Pro | x0.16 | 67.9% (2.0) | 1554 | 1M context |
| Kimi-K2.6 | x0.52 | 66.7% (2.0) | 1484 | **13h/4000+调用** |
| **Kimi-K2.7** | **x0.57** | ~73%+ (2.0) | ~1630+ | **Agent+10%, token-30%** |
| MiniMax-M2.7 | x0.19 | 57.0% (2.0) | 1514 | — |
| DeepSeek-V4-Flash | x0.06 | 56.9% (2.0) | 1395 | 1M context |
| GLM-5.1 | x0.79 | ~55%+ (2.0) | 1535 | — |
| **Hy3** | **x0.00** | — | — | WorkBuddy 90%成功率, ClawEval 68.5 |

### 推理/知识能力

| 模型 | 倍率 | GPQA Diamond |
|------|------|-------------|
| DeepSeek-V4-Pro | x0.16 | 90.1% |
| DeepSeek-V4-Flash | x0.06 | 88.1% |
| GLM-5.2 | x0.79 | **91.2%** |
| **Hy3** | **x0.00** | **90.4%** |

---

## 四、各 Agent 角色选型依据

### Leader（主面板，开发者自选）

| 推荐模型 | 倍率 | 选择依据 |
|---------|------|---------|
| deepseek-v4-pro | x0.16 | Agent Elo **1554**（最高）, Terminal-Bench **67.9%**, SWE-bench **80.6%**, 1M context, **性价比极高** |
| **glm-5.2** | **x0.79** | **Terminal-Bench 81%(全场第2)**, SWE-bench Pro **62.1%**(开源最高), FrontierSWE **74.4%**(接近Opus), Intelligence Index **51**(开源最高), 1M context。**比GLM-5.1质变级提升(Terminal+26pp)** |
| kimi-k2.7 | x0.57 | 编程专用强化版，Code Bench v2 +21.8%、Agent能力+10%、**长程任务token-30%**（有效成本x0.399低于K2.6的x0.52） |

### architect（方案设计）

需求：深度推理 + 系统思维 + 代码理解能力

| 预设 | 模型 | 依据 |
|------|------|------|
| Economic | **deepseek-v4-pro (x0.16)** | SWE-bench **80.6%** 代码理解力对方案设计至关重要。architect 是方向决策者，不能比 coder-senior 弱 |
| Balanced | **glm-5.2 (x0.79)** | Terminal-Bench **81% >> V4-Pro 67.9%** (+13pp), SWE-Pro **62.1% > 55.4%** (+6.7pp), FrontierSWE **74.4%**。architect 是方向决策者，推理+理解深度影响全链路。与 DeepSeek 形成跨厂商审查 |
| Quality | **glm-5.2 (x0.79)** | 公网版无 Claude Opus，GLM-5.2 是公网版最强可用推理+编码模型 |

**为什么 architect 用 GLM-5.2 而非 V4-Pro？**
- 厂商多样性：Balanced 模式 coder-senior/standard/reviewer 已全是 DeepSeek 系，architect 保留 GLM 避免全系 DeepSeek
- GLM-5.2 Terminal-Bench 81% 远超 V4-Pro 67.9%，推理深度影响全链路
- architect 仅 15% token share，成本增量可控

### coder-senior（复杂代码）

需求：最强代码生成 + 架构理解

| 预设 | 模型 | 依据 |
|------|------|------|
| Economic | deepseek-v4-pro (x0.16) | SWE-bench **80.6%**, LiveCodeBench **93.5%** 全场最高, Agent Elo 1554 |
| Balanced | deepseek-v4-pro (x0.16) | 同上。比 GLM-5.1 (x0.79) 便宜 80% 且 Agent Elo 更高 (1554 vs 1535) |
| Quality | deepseek-v4-pro (x0.16) | 公网版无 Claude Sonnet，V4-Pro 是最强可用编码模型 |

### coder-standard（常规代码）

需求：代码生成 + 性价比（25% 最高 token 消耗角色）

| 预设 | 模型 | 依据 |
|------|------|------|
| Economic | deepseek-v4-flash (x0.06) | SWE-bench **79.0%**（比 V3.2 的 ~66% 跳升 13 点）, LiveCodeBench 91.6%, **极低价格强模型** |
| Balanced | deepseek-v4-flash (x0.06) | 同上。25% 最高消耗角色必须极致性价比 |
| Quality | deepseek-v4-pro (x0.16) | SWE-bench 80.6%, 质量模式 standard 也用强模型 |

### coder-lite（简单代码）

需求：模式复制 + 最低成本（升级兜底）

| 预设 | 模型 | 依据 |
|------|------|------|
| Economic | hy3 (x0.00) | SWE-bench 78%+ClawEval 68.5，免费模型中编码能力最强 |
| Balanced | hy3 (x0.00) | 同上。即使偶尔升级到 standard (x0.06)，有效成本仍极低 |
| Quality | deepseek-v4-flash (x0.06) | SWE-bench 79%，质量模式不希望 lite 频繁升级 |

**成本梯度规则：senior > standard > lite**
- Economic: x0.16 > x0.06 > x0.00 ✓
- Balanced: x0.16 > x0.06 > x0.00 ✓
- Quality: x0.16 > x0.16 > x0.06 ✓

### reviewer（代码审查）

需求：代码理解 + 推理（找 bug、验规范）

| 预设 | 模型 | 依据 |
|------|------|------|
| Economic | hy3 (x0.00) | SWE-bench 78%代码理解+GPQA 90.4%推理，经济模式审查够用 |
| Balanced | **deepseek-v4-pro (x0.16)** | SWE-bench **80.6%** 代码理解强, GPQA **90.1%** 推理强 |
| Quality | **kimi-k2.7 (x0.57)** | **跨厂商审查**：coder 用 DeepSeek(V4-Pro)，reviewer 用 Kimi 提供第三方视角。编程专用强化，Agent+10%, token-30% |

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
| Balanced | **kimi-k2.7 (x0.57)** | 编程专用强化版，Agent能力+10%, **长程任务token-30%**, agent+tool-use 标签。有效成本x0.399低于K2.6的x0.52 |
| Quality | **kimi-k2.7 (x0.57)** | 同 Balanced。公网版无 Gemini 3.5 Flash，K2.7 是 Agent 能力最强的可用替代 |

**Balanced 为什么 tester 用 Kimi 而非 V4-Pro？**
- **厂商多样性**：Balanced 模式 coder-senior/standard/reviewer 已全是 DeepSeek 系，tester 保留 Kimi 避免全系 DeepSeek
- Kimi 长会话稳定性极佳（13h/4000+调用不降级）
- K2.7 Terminal-Bench ~73%+ 超过 V4-Pro 的 67.9%

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
| Economic | hy3 (x0.00) | 公网版唯一免费模型，与 Leader (V4-Pro) 不同厂商 |
| Balanced | hy3 (x0.00) | 公网版唯一免费模型，与 Leader 不同厂商 |
| Quality | hy3 (x0.00) | 公网版唯一免费模型，与 Leader (V4-Pro) 不同厂商 |

> **注意**：Kimi-K2.5 在公网版已不再免费 (x0.45)，goal-evaluator 改用 hy3（免费）。虽然 hy3 与 coder-lite 同模型，但 goal-evaluator 仅读取验证报告做 yes/no 判定，不执行代码，模型独立性风险可控。

### director（最终裁决）

需求：最强推理 + 根因分析能力

| 预设 | 模型 | 依据 |
|------|------|------|
| Economic | glm-5.2 (x0.79) | 公网版最强可用推理模型。Terminal-Bench 81%, GPQA 91.2% |
| Balanced | glm-5.2 (x0.79) | 同上。Director 仅在 3 轮全败时激活 1 次，token 消耗可控 |
| Quality | glm-5.2 (x0.79) | 公网版无 Claude Opus，GLM-5.2 是最强替代 |

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

> **结论：GLM-5v-Turbo 不适合作为预设中的通用 agent 模型，但在需要视觉输入的前端/UI 任务中是当前最佳选择。** 建议作为 `agent custom` 的可选模型。价格 x0.95，视觉能力是增值。

---

## 五、厂商多样性分析

### 经济模式

| 厂商 | 覆盖角色 | 倍率 |
|------|---------|------|
| DeepSeek | architect, coder-senior, coder-standard | x0.06~x0.16 |
| Hy3 | coder-lite, reviewer, reviewer-b, tester, recorder, goal-evaluator | x0.00 |
| GLM | director | x0.79 |

> DeepSeek 承担架构设计+代码生成，Hy3 承担审查+测试+归档+目标验证。成本 x0.06，仍极低。

### 平衡模式

| 厂商 | 覆盖角色 | 倍率 |
|------|---------|------|
| Z.AI (GLM) | architect, director | x0.79 |
| DeepSeek | coder-senior, coder-standard, reviewer | x0.06~x0.16 |
| Hy3 | coder-lite, recorder, goal-evaluator | x0.00 |
| Kimi | reviewer-b, tester | x0.57 |

> **四厂商覆盖**：GLM-5.2 负责架构设计+裁决，DeepSeek 负责代码生成+主审，Kimi 负责辅审+测试，Hy3 负责简单代码+归档+目标验证。architect 与 reviewer 不同厂商，形成跨厂商审查。成本 x0.32。

### 质量模式

| 厂商 | 覆盖角色 | 倍率 |
|------|---------|------|
| Z.AI (GLM) | architect, director | x0.79 |
| DeepSeek | coder-senior, coder-standard, coder-lite, reviewer-b | x0.06~x0.16 |
| Kimi | reviewer, tester | x0.57 |
| Hy3 | recorder, goal-evaluator | x0.00 |

> 公网版无 Claude/GPT/Gemini，质量模式通过 GLM+DeepSeek+Kimi 三厂商组合最大化质量。DeepSeek V4-Pro 全线代码 + Kimi 主审交叉验证 + GLM 架构裁决。

---

## 六、模型选择铁律

1. **成本梯度不可倒挂**：senior > standard > lite（任何预设）
2. **角色匹配优先于厂商偏好**：选对能力 > 选便宜的
3. **审查与编码不同厂商**：减少"自己写自己审"的同系盲区
4. **免费模型物尽其用**：hy3 SWE-bench 78%+GPQA 90.4%+ClawEval 68.5，公网版唯一免费模型
5. **数据说话**：选型必须有 Benchmark 支撑，禁止"感觉这个模型好"
6. **公网版约束**：仅使用 CodeBuddy 国内个人体验版可用的模型，不支持 Claude/GPT/Gemini

---

## 七、数据来源

| 来源 | URL | 数据类型 |
|------|-----|---------|
| SWE-bench 官方 | swebench.com | Verified / Pro 排行榜 |
| DeepSeek V4 技术报告 | Hugging Face model card (2026-04-24) | 官方 Benchmark |
| Z.AI / 智谱官方 | open.bigmodel.cn / labellerr.com (2026-06-13) | GLM-5.2 官方 Benchmark |
| 腾讯混元官方 | 腾讯云 TokenHub / Hy3 正式发布 (2026-07-06) | Hy3 正式版 Benchmark (SWE-bench 78%、GPQA 90.4%、ClawEval 68.5) |
| thesys.dev | thesys.dev/blogs/deepseek-v4-pro | 独立对比评测 |
| coderouter.io | coderouter.io/blog/deepseek-v4-pro-vs-v4-flash-coding | 独立编码评测 |
| particula.tech | particula.tech/blog/deepseek-v4-vs-kimi-k2-6-vs-glm-5-1 | 开源模型横评 |
| sotasync.com | sotasync.com/reader/2026-04-30-kimi-k2-vs-glm-5 | 国产模型编程对决 |
| dev.to | dev.to/jamilxt/glm-52-vs-claude-opus | GLM-5.2 vs Opus 独立审计 |
| emergentmind.com | emergentmind.com/topics/glm-5v-turbo | GLM-5v-Turbo 技术解析 |
| CodeSOTA | codesota.com/llm/coding-benchmarks | 编码 Benchmark 汇总 |
