# 模型选择依据与 Benchmark 数据

> 本文档记录 Beggar 三档预设方案中每个模型选择的 Benchmark 数据依据。
> 数据来源：官方技术报告、swebench.com、独立评测（thesys.dev、coderouter.io、particula.tech、sotasync.com）
> 最后更新：2026-07-07

---

## 一、核心 Benchmark 指标说明

| 指标 | 测试内容 | 为什么重要 |
|------|---------|-----------|
| **SWE-bench Verified** | 真实 GitHub Issue 修复率（500 个人工验证问题） | 最接近"模型能不能干真实编码活"的评测 |
| **SWE-bench Pro** | 731 个未公开真实 Issue（更难，防数据污染） | 衡量最难编码任务的上限 |
| **LiveCodeBench** | 编程竞赛通过率 | 衡量代码生成纯能力 |
| **Terminal-Bench 2.0/2.1** | 真实终端环境多步任务（读输出、处理错误、迭代） | 衡量 Agent 执行命令+分析结果能力 |
| **MCP Atlas** | 大规模工具调用可靠性测试（数百个任务） | 衡量 Agent tool-use 稳定性 |
| **Agent Elo (GDPval-AA)** | 真实世界智能体任务排名 | 综合 Agent 能力排名 |
| **HLE (Humanity's Last Exam)** | 世界知识+推理深度 | 衡量知识广度和最深层推理 |
| **GPQA Diamond** | 研究生级别科学问答 | 衡量推理深度 |

---

## 二、全模型 Benchmark 数据矩阵

### 编码能力

| 模型 | 平台倍率 | SWE-bench Verified | SWE-bench Pro | LiveCodeBench |
|------|---------|-------------------|---------------|---------------|
| Claude-Opus-4.7 | x3.33 | **87.6%** | **64.3%** | — |
| GPT-5.5 | x3.31 | ~88.7% | ~58.6% | — |
| DeepSeek-V4-Pro | x0.13 | **80.6%** | 55.4% | **93.5%** |
| Kimi-K2.6 | x0.50 | 80.2% | **58.6%** | — |
| **Kimi-K2.7** 🆕 | **x0.65** | ~82%+ | **~65%+** | — |
| Claude-Sonnet-4.6 | x2.00 | 79.6% | — | — |
| DeepSeek-V4-Flash | x0.05 | **79.0%** | — | 91.6% |
| GLM-5.2 | x1.06 | **~82%** 🔥 | **62.1%** 🆙 | **93.5%** |
| GLM-5.1 | x0.90 | 78.9% | 58.4% | — |
| Claude-Haiku-4.5 | x0.67 | ~73.3% | — | — |
| **Hy3** | **x0.00** | **78.0%** | **57.9%** | — |
| DeepSeek-V3.2 | x0.15 | ~66% | — | — |
| Gemini-2.5-Pro | x0.90 | ~63.8% | — | — |
| GPT-5.1-Codex | x0.90 | — | — | — |
| GPT-5.1-Codex-Mini | x0.18 | — | — | — |
| MiniMax-M2.7 | x0.19 | — | 56.2% | — |

### Agent/工具使用能力

| 模型 | 倍率 | Terminal-Bench | MCP Atlas | Agent Elo | 长会话稳定性 |
|------|------|--------------|-----------|-----------|------------|
| Gemini-3.5-Flash | x0.99 | **76.2%** (2.1) | **83.6%** | **1656** | 289 tok/s |
| Gemini-3.1-Pro | x1.32 | 70.3% (2.1) | 78.2% | 1314 | — |
| DeepSeek-V4-Pro | x0.13 | 67.9% (2.0) | — | 1554 | 1M context |
| Kimi-K2.6 | x0.50 | 66.7% (2.0) | — | 1484 | **13h/4000+调用** |
| **Kimi-K2.7** 🆕 | **x0.65** | ~73%+ (2.0) | — | ~1630+ | **Agent能力+10%, token-30%** |
| Claude-Opus-4.7 | x3.33 | 65.4% (2.0) | — | — | — |
| MiniMax-M2.7 | x0.19 | 57.0% (2.0) | — | 1514 | — |
| DeepSeek-V4-Flash | x0.05 | 56.9% (2.0) | — | 1395 | 1M context |
| GLM-5.2 | x1.06 | **81.0%** (2.1) 🔥 | **76.8%** 🆙 | **~1580** | 1M context |
| GLM-5.1 | x0.90 | ~55%+ (2.0) | — | 1535 | — |
| **Hy3** | **x0.00** | — | — | — | WorkBuddy 90%成功率, ClawEval 68.5 |

### 推理/知识能力

| 模型 | 倍率 | HLE | GPQA Diamond | HMMT 2026 (数学) |
|------|------|-----|-------------|-----------------|
| Gemini-3.1-Pro | x1.32 | **44.4%** | — | — |
| Gemini-3.5-Flash | x0.99 | 40.2% | — | — |
| Claude-Opus-4.7 | x3.33 | 40.0% | **94.2%** | **96.2%** |
| GPT-5.5 | x3.31 | 39.8% | — | 97.7% |
| DeepSeek-V4-Pro | x0.13 | 37.7% | 90.1% | 95.2% |
| DeepSeek-V4-Flash | x0.05 | 34.8% | 88.1% | 94.8% |
| GLM-5.2 | x1.06 | ~40.5% | **91.2%** 🆙 | **96.5%** |
| **Hy3** | **x0.00** | — | **90.4%** | — |

---

## 三、各 Agent 角色选型依据

### Leader（主面板，开发者自选）

| 推荐模型 | 倍率 | 选择依据 |
|---------|------|---------|
| deepseek-v4-pro | x0.13 | Agent Elo **1554**（最高）, Terminal-Bench **67.9%**, SWE-bench **80.6%**, 1M context, **48%降价后性价比极高** |
| **glm-5.2** 🆙 | **x1.06** | **Terminal-Bench 81%(全场第2)**, SWE-bench Pro **62.1%**(开源最高), FrontierSWE **74.4%**(接近Opus4.8), Intelligence Index **51**(开源最高), 1M context, MIT开源。**比GLM-5.1质变级提升(Terminal+26pp, SWE-Pro+3.7pp)** |
| kimi-k2.7 🆕 | x0.65 | 编程专用强化版，Code Bench v2 +21.8%、Agent能力+10%、**长程任务token-30%**（有效成本x0.455低于K2.6），agent+tool-use+long-context 标签 |
| claude-opus-4.7-1m | x3.33 | SWE-bench **87.6%**, GPQA **94.2%**, 最强推理保证分派精准（质量模式） |

> **🆕 GLM-5.2 定位**：开源最强文本模型，编码/Agent 能力进入第一梯队。价格介于 V4-Pro(x0.13) 和 Sonnet(x2.00) 之间。适合追求"接近 Claude 水准但只要 1/3 价格"的场景。Terminal-Bench 81% 甚至超过 Opus 4.7(65.4%)，在终端操作类任务上表现卓越。

### architect（方案设计）

需求：深度推理 + 系统思维 + 代码理解能力

| 预设 | 模型 | 依据 |
|------|------|------|
| Economic | **deepseek-v4-pro (x0.13)** | SWE-bench **80.6%** 代码理解力对方案设计至关重要。architect 是方向决策者，不能比 coder-senior 弱。增量仅 +x0.02（x0.03→x0.05），性价比极高 |
| Balanced | **glm-5.2 (x1.06)** | Terminal-Bench **81% >> V4-Pro 67.9%** (+13pp), SWE-Pro **62.1% > 55.4%** (+6.7pp), FrontierSWE **74.4%**。architect 是方向决策者，推理+理解深度影响全链路。成本从 x0.12 升至 x0.29，但 architect 仅 15% token share，增量可控 |
| Quality | claude-opus-4.7-1m (x3.33) | SWE-bench Pro **64.3%**（最难任务最高）, GPQA **94.2%**, 系统设计用最强推理 |

**为什么不用 Gemini-2.5-Pro？**
- Gemini-2.5-Pro 频繁路由到不可用 region (us-south1)，已弃用作为 agent 模型
- DeepSeek-V4-Pro 降价后 x0.13 性价比极高，且 SWE-bench 80.6% 远高于 Gemini 63.8%
- architect 需要深入理解代码结构来设计方案，代码理解能力比纯推理深度更关键
- 厂商多样性通过 Kimi (tester) 保障

### coder-senior（复杂代码）

需求：最强代码生成 + 架构理解

| 预设 | 模型 | 依据 |
|------|------|------|
| Economic | deepseek-v4-pro (x0.13) | SWE-bench **80.6%** ≈ Opus, LiveCodeBench **93.5%** 全场最高, Agent Elo 1554 |
| Balanced | deepseek-v4-pro (x0.13) | 同上。比 GLM-5.1 (x0.90) 便宜 86% 且 Agent Elo 更高 (1554 vs 1535) |
| Quality | claude-sonnet-4.6-1m (x2.00) | SWE-bench 79.6%, 比 Opus 便宜 40%。最难任务（SWE-bench Pro）Claude 系 64.3% 远超 V4-Pro 55.4% |

**为什么 Quality 不全用 V4-Pro？**
- SWE-bench Pro（ hardest tasks）: Claude 64.3% vs V4-Pro 55.4%（差 9 点）
- Claude 的指令遵循能力在极复杂架构/安全任务中仍有优势
- Quality 模式就是为最难的 task 设计，差 9 点 SWE-bench Pro 值得花 x2.00

**🆙 GLM-5.2 在 senior 的位置？**
- GLM-5.2 (x1.06): SWE-bench Pro 62.1%, 比 Sonnet(x2.00)便宜 47%
- 但 Claude 在 SWE-bench Pro 上仍领先 2+ 点，且复杂架构任务的指令遵循更可靠
- 结论: senior 暂不建议替换 Sonnet，除非预算敏感且愿意接受略低的最难任务成功率

### coder-standard（常规代码）

需求：代码生成 + 性价比（25% 最高 token 消耗角色）

| 预设 | 模型 | 依据 |
|------|------|------|
| Economic | deepseek-v4-flash (x0.05) | SWE-bench **79.0%**（比 V3.2 的 ~66% 跳升 13 点）, LiveCodeBench 91.6%, **极低价格强模型** |
| Balanced | deepseek-v4-flash (x0.05) | 同上。25% 最高消耗角色必须极致性价比 |
| Quality | deepseek-v4-pro (x0.13) | SWE-bench 80.6%, 质量模式 standard 也用强模型。比 GPT-5.1-Codex (x0.90) 更强更便宜 |

### coder-lite（简单代码）

需求：模式复制 + 最低成本（升级兜底）

| 预设 | 模型 | 依据 |
|------|------|------|
| Economic | hy3 (x0.00) | SWE-bench 78%+ClawEval 68.5，免费模型中编码能力最强。"找参照→复制→微调"指引降低硬需求 |
| Balanced | hy3 (x0.00) | 同上。即使偶尔升级到 standard (x0.05)，有效成本仍极低 |
| Quality | deepseek-v4-flash (x0.05) | SWE-bench 79%，质量模式不希望 lite 频繁升级浪费时间 |

**成本梯度规则：senior > standard > lite**
- Economic: x0.13 > x0.05 > x0.00 ✓
- Balanced: x0.13 > x0.05 > x0.00 ✓
- Quality: x2.00 > x0.13 > x0.05 ✓

### reviewer（代码审查）

需求：代码理解 + 推理（找 bug、验规范）

| 预设 | 模型 | 依据 |
|------|------|------|
| Economic | hy3 (x0.00) | SWE-bench 78%代码理解+GPQA 90.4%推理，经济模式审查够用 |
| Balanced | **deepseek-v4-pro (x0.13)** | SWE-bench **80.6%** 代码理解碾压 Gemini-2.5-Pro (63.8%), GPQA **90.1%** 推理强。与 architect(GLM-5.2/Z.AI) 形成跨厂商审查 |
| Quality | **kimi-k2.7 (x0.65)** | **跨厂商审查**：coder 用 Claude(sonnet)+DeepSeek(V4-Pro)，reviewer 用 Kimi 提供第三方视角。编程专用强化，Code Bench v2 +21.8%, Agent能力+10%, token-30% |

**Balanced 为什么 reviewer 用 V4-Pro？**

关键数据对比：
| 指标 | V4-Pro (x0.13) | Gemini-2.5-Pro (x0.90) |
|------|---------------|----------------------|
| SWE-bench（代码理解） | **80.6%** | 63.8% |
| GPQA Diamond（推理） | **90.1%** | — |
| Terminal-Bench（工具执行） | **67.9%** | — |
| 价格 | **x0.13** | x0.90 |

- 代码理解差 17 个点（80.6% vs 63.8%）是决定性差距
- reviewer 的核心能力是"看懂代码+发现问题"，代码理解力比纯推理更重要
- V4-Pro 降价后 x0.13，便宜 86% 且代码审查能力远强于 Gemini
- 厂商多样性通过 Kimi (tester) 保证

**Quality 为什么 reviewer 用 Kimi 而非 V4-Pro？**
- Quality 模式 coder-senior 用 Sonnet(Claude)，coder-standard 用 V4-Pro(DeepSeek)
- 如果 reviewer 也用 V4-Pro，会和 coder-standard 形成同系审查盲区
- Kimi 作为第三方厂商提供独立的审查视角
- Kimi 实测 13h/4000+ 调用不降级，长会话审查稳定可靠
- 辅审 reviewer-b 用 V4-Pro (x0.13)，补充代码深度
- 降价后 V4-Pro 极其便宜(x0.13)，存在"全用 DeepSeek 就行"的诱惑，但跨厂商审查的价值不应仅用成本衡量

### tester（测试验证）

需求：执行命令 + 分析结果 + 工具调用

| 预设 | 模型 | 依据 |
|------|------|------|
| Economic | hy3 (x0.00) | WorkBuddy任务成功率90%+ClawEval 68.5，Agent能力强 |
| Balanced | **kimi-k2.7 (x0.65)** | 编程专用强化版，Agent能力+10%, **长程任务token-30%**, agent+tool-use 标签。有效成本x0.455低于K2.6 |
| Quality | **gemini-3.5-flash (x0.99)** | Terminal-Bench **76.2%** 全场最高, MCP Atlas **83.6%** 全场最高, Agent Elo **1656** 全场最高 |

**Balanced 为什么 tester 用 Kimi 而非 V4-Pro？**

| 指标 | V4-Pro (x0.13) | Kimi-K2.7 (x0.65) |
|------|---------------|-------------------|
| Terminal-Bench | **67.9%** | ~73%+ (基线66.7%+10%提升) |
| Agent Elo | **1554** | ~1630+ (基线1484+10%提升) |
| Token消耗 | 基准 | **-30%**（编程专用优化） |
| 倍率 | x0.13 | x0.65 (有效成本x0.455) |

- V4-Pro 在 Terminal-Bench 上略胜，但 K2.7 编程专用强化后 Agent 能力 +10%
- K2.7 长程任务 token 消耗 -30%，有效成本 x0.455 反低于 K2.6 的 x0.50
- **更重要的是厂商多样性**：Balanced 模式 coder-senior/standard/reviewer 已全是 DeepSeek 系，tester 保留 Kimi 避免全系 DeepSeek

### recorder（知识沉淀）

需求：理解和总结能力（最低优先级）

| 预设 | 模型 | 依据 |
|------|------|------|
| Economic | hy3 (x0.00) | SWE-bench 78%+reasoning，5% 最低 token 占比 |
| Balanced | hy3 (x0.00) | 同上，不值得在最低优先级角色花钱 |
| Quality | claude-haiku-4.5 (x0.67) | Claude 指令遵循好，质量模式归档统一规范 |

---

### 🆕 GLM-5v-Turbo（多模态视觉编程）

> **定位**：原生多模态 Coding 基座，从预训练阶段融合视觉与文本。不是"文本模型+看图插件"，而是底层统一建模。

**核心 Benchmark（多模态赛道）**

| 指标 | GLM-5v-Turbo | Kimi K2.5 | Claude Opus 4.6 |
|------|-------------|-----------|-----------------|
| Design2Code（设计稿→代码）| **94.8%** 🔥 | 91.3% | 77.3% |
| BrowseComp-VL（浏览理解）| **51.9%** | 42.9% | 35.9% |
| MMSearch（多模态搜索）| **72.9%** | 58.7% | 63.8% |
| AndroidWorld（GUI Agent）| **75.7%** | 43.1% | 62.0% |
| OSWorld（桌面 GUI Agent）| 62.3% | 63.3% | **72.2%** |
| WebVoyager（Web Agent）| **88.5%** | 84.3% | 88.0% |

**纯文本编码能力（未退化）**

| 指标 | GLM-5v-Turbo | GLM-5-Turbo | Claude Opus 4.6 |
|------|-------------|-------------|-----------------|
| CC-Frontend | 68.4% | 69.4% | **75.9%** |
| CC-Backend | 22.8% | 20.5% | **26.9%** |
| CC-RepoExploration | **72.2%** | 68.9% | **74.4%** |

**在 Beggar 工作流中的适用场景**

| 场景 | 适用度 | 说明 |
|------|--------|------|
| UI/前端开发（设计稿→代码）| ⭐⭐⭐⭐⭐ | Design2Code 94.8% 全场最高 |
| 截图分析 / Bug 复现 | ⭐⭐⭐⭐ | 原生视觉理解，无需额外 OCR |
| Web 开发（HTML/CSS 为主）| ⭐⭐⭐⭐ | Vision2Web + BrowseComp-VL 双强 |
| 后端逻辑代码 | ⭐⭐⭐ | 纯文本能力持平 GLM-5-Turbo，但不如纯文本模型划算 |
| 通用 Agent 编排 | ⭐⭐⭐ | x0.81 价格合理，但非最优选择 |

> **结论：GLM-5v-Turbo 不适合作为预设中的通用 agent 模型，但在需要视觉输入的前端/UI 任务中是当前最佳选择。** 建议作为 `agent custom` 的可选模型或新增 `visual` 类别专用模型。价格 x0.81 比 GLM-5.1(x0.90) 还便宜，视觉能力是白送的增值。

---

## 四、厂商多样性分析

### 经济模式

| 厂商 | 覆盖角色 | 倍率 |
|------|---------|------|
| DeepSeek | architect, coder-senior, coder-standard | x0.05~x0.13 |
| Hunyuan (Hy3) | coder-lite, reviewer, tester, recorder | x0.00 |
| Hunyuan (Hunyuan-2.0) | reviewer-b | x0.00 |

> architect 升级为 V4-Pro 后，DeepSeek 承担架构设计+代码生成，Hy3 承担审查+测试+归档。成本 x0.05，仍极低。Hy3 SWE-bench 78% 远超前代，architect 不再用免费模型避免方向决策者能力不足。

### 平衡模式

| 厂商 | 覆盖角色 | 倍率 |
|------|---------|------|
| Z.AI (GLM-5.2) | architect | x1.06 |
| DeepSeek | coder-senior, coder-standard, reviewer | x0.05~x0.13 |
| Hunyuan (Hy3) | coder-lite, recorder | x0.00 |
| Moonshot (Kimi) | reviewer-b, tester | x0.65 |

> **三厂商覆盖**：GLM-5.2 负责架构设计（Terminal-Bench 81%），DeepSeek 负责代码生成+主审（SWE-bench 80.6%），Kimi 负责辅审+测试（编程专用强化，token-30%）。architect 与 reviewer 不同厂商，形成跨厂商审查。成本 x0.29，比原 V4 全链路(x0.12)贵约 2.4 倍，但 architect 推理能力质变级提升。

### 质量模式

| 厂商 | 覆盖角色 |
|------|---------|
| Anthropic (Claude) | architect, coder-senior, recorder |
| DeepSeek | coder-standard, coder-lite, reviewer-b |
| Moonshot (Kimi) | reviewer |
| Google (Gemini) | tester |

> Claude 写架构+核心代码 → Kimi 主审（第三视角）+ DeepSeek 辅审（代码深度）→ Gemini 测试（Terminal-Bench 最高）。形成三方审查+最强测试的交叉验证体系。
> 
> 过去 Gemini-2.5-Pro 被安排在 reviewer 位置，因路由到不可用 region (us-south1) 问题弃用，改由 Kimi 担任主审。

---

## 五、模型选择铁律

1. **成本梯度不可倒挂**：senior > standard > lite（任何预设）
2. **角色匹配优先于厂商偏好**：选对能力 > 选便宜的
3. **审查与编码不同厂商**：减少"自己写自己审"的同系盲区
4. **免费模型物尽其用**：hy3 SWE-bench 78%+GPQA 90.4%+ClawEval 68.5，免费模型中综合最强
5. **数据说话**：选型必须有 Benchmark 支撑，禁止"感觉这个模型好"

---

## 六、数据来源

| 来源 | URL | 数据类型 |
|------|-----|---------|
| SWE-bench 官方 | swebench.com | Verified / Pro 排行榜 |
| DeepSeek V4 技术报告 | Hugging Face model card (2026-04-24) | 官方 Benchmark |
| Anthropic 官方 | anthropic.com (Opus 4.7/4.8 发布) | Claude 系列 Benchmark |
| Google I/O 2026 | blog.google (2026-05-19) | Gemini 3.5 Flash 数据 |
| Z.AI / 智谱官方 | open.bigmodel.cn / labellerr.com (2026-06-13) | GLM-5.2 官方 Benchmark |
| 腾讯混元官方 | 腾讯云 TokenHub / Hy3 正式发布 (2026-07-06) | Hy3 正式版 Benchmark (SWE-bench 78%、GPQA 90.4%、ClawEval 68.5) |
| thesys.dev | thesys.dev/blogs/deepseek-v4-pro | 独立对比评测 |
| coderouter.io | coderouter.io/blog/deepseek-v4-pro-vs-v4-flash-coding | 独立编码评测 |
| particula.tech | particula.tech/blog/deepseek-v4-vs-kimi-k2-6-vs-glm-5-1 | 开源模型横评 |
| sotasync.com | sotasync.com/reader/2026-04-30-kimi-k2-vs-glm-5 | 国产模型编程对决 |
| dev.to | dev.to/jamilxt/glm-52-vs-claude-opus | GLM-5.2 vs Opus 独立审计 |
| expertbeacon.com | expertbeacon.com/what-glm-5-2-is | GLM-5.2 综合评测 |
| Artificial Analysis | artificialanalysis.ai | Intelligence Index 排名 |
| BenchLM (Design2Code) | benchlm.ai/benchmarks/design2Code | 多模态编程基准 |
| emergentmind.com | emergentmind.com/topics/glm-5v-turbo | GLM-5v-Turbo 技术解析 |
| CodeSOTA | codesota.com/llm/coding-benchmarks | 编码 Benchmark 汇总 |
