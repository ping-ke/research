# Bittensor SN19 & SN64 评分机制深度解析

> 研究日期：2026-05-11  
> 适用版本：dTAO 时代（2025.02 至今）

---

## 概述

| | **SN19 · Nineteen AI** | **SN64 · Chutes** |
|---|---|---|
| 定位 | 去中心化 LLM 推理 + 图像生成 | 去中心化无服务器 AI 算力平台 |
| 维护方 | Rayon Labs (namoray) | Rayon Labs |
| GitHub | [namoray/nineteen](https://github.com/namoray/nineteen) | [rayonlabs/chutes-api](https://github.com/rayonlabs/chutes-api) |
| 官网 | [sn19.ai](https://sn19.ai) | [chutes.ai](https://chutes.ai) |
| 核心哲学 | **快 = 好**（速度即质量） | **真实 = 可信**（密码学保证来源） |

---

## SN19 · Nineteen AI 评分机制

### 架构：DSIS（去中心化规模推断子网）

每个 Validator 运营独立 API 网关，对外销售推断访问权限。  
矿工无法屏蔽 Validator 的查询，合成查询与有机（真实用户）查询对矿工不可区分。

### 三层评分公式

```
Final_Score = Σ [ task_weight_i × task_score_i ]
                                    ↓
                 task_score_i = period_score_i × combined_quality_score_i
                                                          ↓
                                combined_quality_score_i = quality_score × speed_factor
```

#### 第一层：Period Score（可用性分）

```
period_score = 成功响应数 / 被测试总请求数
```

- 每 **60 分钟**为一个评分周期（来源：[sn19.ai/docs/about](https://sn19.ai/docs/about)）
- Validator 先获取 miner 声明的处理容量，按比例抽样测试
- 矿工可主动发出**限速信号（Rate Limit）**，不受惩罚
- 声称高容量但实际响应低 → 按空置量比例扣分

#### 第二层：Quality × Speed（质量×速度分）

> **重要澄清**：LLM 文本任务的 `quality_score` 本质上是速度与完成度的复合分，**不存在语义质量评估**。

| 任务类型 | 质量评分方式 | 速度指标 |
|---|---|---|
| **LLM 文本** | 响应完整性 + HTTP 成功率 | TTFT（首 token 时延）+ TPS（tokens/s） |
| **图像生成** | 视觉 Embedding 相似度 vs 参考图像（Seed Matching） | 图像生成总延迟 |
| **Embedding** | 向量余弦相似度 | 响应时间 |

**为什么 LLM 文本没有语义质量评分？**

1. 开放式对话无"参考答案"可比对
2. LLM 非确定性（浮点精度 + 并行）使相同 prompt 在不同硬件输出不同
3. 若用语义相似度打分，会激励矿工使用输出更保守的轻量模型来刷分

   **Q：为什么保守的轻量模型反而得高分？**

   假设评分流程如下：
   ```
   Validator 用自己的模型生成「参考答案」
       ↓
   将矿工回答与参考答案分别转为 Embedding 向量
       ↓
   计算余弦相似度，越高 → 分越高
   ```

   问题在于：**语义相似度奖励的是"和参考答案像不像"，而非"回答质量高不高"。**

   | | 输出风格 | 与参考答案相似度 |
   |---|---|---|
   | 小模型（7B） | 公式化、保守，给出最"主流"的答案 | **高**（紧贴平均答案） |
   | 大模型（70B） | 有深度，补充细节、反驳观点，给出非预期角度 | **低**（语义发散） |

   大模型给出了更有价值的回答，却因"偏离参考答案"而得低分。  
   矿工最优策略：用最小、最快、输出最保守的模型——省成本、得高分、双赢。  
   结果：网络里全是输出平庸内容的轻量模型，真正有能力的大模型反而出局。


  举个例子，问题是 "区块链有什么优点"：

   |   | 输出 | 相似度 |
   |---|---|---|
   | 参考答案（Validator 模型）| "去中心化、透明、不可篡改" | — |
   | 小模型 | "去中心化、透明、安全不可篡改" | 0.97（几乎一样）   |
   | 大模型 | "去中心化确实是优点，但在企业场景下性能瓶颈和治理复杂度往往是更大的挑战，需要权衡..." | 0.72（语义发散了）|

   这是 **Goodhart 定律**的经典体现：当一个指标变成目标，它就不再是好指标。

#### 第三层：跨任务加权汇总

各任务权重由代码中的 `task_config` 决定，矿工可自选参与任务，未参与不扣分。具体各任务权重比例待核实（来源：[namoray/nineteen](https://github.com/namoray/nineteen) 源码）。

### 数值例子

> 假设各任务权重为：LLM 0.65、图像 0.35（具体权重待 [namoray/nineteen](https://github.com/namoray/nineteen) 源码确认）

| 指标 | Miner A（H100） | Miner B（4×A100，仅 LLM） |
|---|---|---|
| LLM 响应成功率 | 98/100 = **0.98** | 55/60 = **0.917** |
| LLM 速度因子 | ×1.15（TTFT 0.8s） | ×0.92（TTFT 1.8s） |
| 图像响应成功率 | 48/50 = **0.96** | 不参与 |
| 图像质量×速度 | 0.88 × 1.10 = **0.968** | — |

```
Miner A：
  LLM  task = 0.98 × (1.00 × 1.15) = 0.911
  图像 task = 0.96 × (0.88 × 1.10) = 0.835
  Final     = 0.65×0.911 + 0.35×0.835 = 0.884

Miner B：
  LLM  task = 0.917 × (1.00 × 0.92) = 0.770
  图像 task = 0（未参与）
  Final     = 0.65×0.770 = 0.501

→ Miner A 权重高出约 77%
```

### 防作弊机制

| 机制 | 原理 |
|---|---|
| **不可预测随机种子** | 图像任务用无法预测的种子，矿工无法预缓存结果伪造速度 |
| **容量声明惩罚** | 声称 10k tokens/min 实际只能跑 2k → 空置量计入惩罚 |
| **限速安全港** | 矿工资源紧张时可显式限速，不受惩罚，保证网络负载均衡 |
| **Organic Query 混入** | 有机真实请求和合成请求对矿工不可区分，无法只对测试请求优化 |
| **去中心化 Checking Server** | Validator 用自身硬件的独立服务器评分，无中心化评分机构 |

---

## SN64 · Chutes 评分机制

### 架构：去中心化无服务器 AI 算力

矿工（GPU 运营商）注册硬件并部署模型为 "Chute" 端点，开发者通过标准 API 发送推断请求。

**核心评分逻辑：** [`rayonlabs/chutes-audit`](https://github.com/rayonlabs/chutes-audit)（权重复现与审计脚本）

### 评分公式（7 天滚动窗口）

来源：[Chutes 评分文档](https://chutes.ai/docs/miner-resources/scoring)

```python
final_score = (0.55 × normalized_compute)       # 速度隐含其中（step_time/token_time 归一化）
            + (0.15 × chute_diversity_score)
            + (0.05 × normalized_bounty)
            + (? × normalized_invocation_count)  # 官方文档确认存在，具体权重未公开，补足剩余 25%
```

#### 1. Compute Units（55%）——GPU 算力时间

```
compute_units = GPU_hours × compute_multiplier
normalized    = compute_units_i / Σ(all_miners_compute_units)
```

- 用 **2 天滚动中位速率**（`step_time` / `token_time`）标准化
- 速度快的 miner 等效算力更高（速度隐含其中）
- 只统计成功的 invocation

#### 2. Chute Diversity Score（15%）——多样性/可用性

```python
# 两档指数归一化，严惩低于中位数的矿工
if chute_count >= median:
    raw = (chute_count / max_count) ** 1.3   # 温和增益
else:
    raw = (chute_count / max_count) ** 2.2   # 陡峭惩罚
```

- 按 GPU 需求加权（4-GPU chute 权重 = 4 × 1-GPU chute）
- 每小时快照取平均

#### 3. Bounty（5%）——首发悬赏

- 第一个成功处理某新 Chute 推理的矿工获得奖励
- 只计次数，含**几何衰减**（同一 chute 后续价值递减）
- `normalized_bounty = bounty_count_i / Σ(all miners)`

**防多号刷分：** 同一 coldkey 下多个 hotkey，只有最高分保留，其余归零。

### 数值例子

> 以下仅展示权重已公开的三项（55% + 15% + 5% = 75%）；invocation_count 约占剩余 25%，官方未公开权重，不纳入此例。

| 指标 | Miner A（高算力） | Miner B（高 Bounty） | Miner C（均衡） |
|---|---|---|---|
| 7天 compute | 1000 GPU-h | 400 GPU-h | 600 GPU-h |
| 唯一 Chute 数（GPU加权） | 8 | 3 | 6（=中位数） |
| 7天 Bounty 次数 | 2 | 5 | 3 |

```
Compute 归一化（总=2000）：
  A = 1000/2000 = 0.500
  B = 400/2000  = 0.200
  C = 600/2000  = 0.300

Chute 分（中位=6, 最大=8）：
  A: (8/8)^1.3 = 1.000 → 归一化 0.561
  B: (3/8)^2.2 ≈ 0.098 → 归一化 0.055  ← 低于中位，惩罚显著
  C: (6/8)^1.3 ≈ 0.685 → 归一化 0.384

Bounty 归一化（总=10）：
  A = 0.200, B = 0.500, C = 0.300

三项合计分（不含 invocation_count）：
  A = 0.55×0.500 + 0.15×0.561 + 0.05×0.200 = 0.275+0.084+0.010 = 0.369
  B = 0.55×0.200 + 0.15×0.055 + 0.05×0.500 = 0.110+0.008+0.025 = 0.143
  C = 0.55×0.300 + 0.15×0.384 + 0.05×0.300 = 0.165+0.058+0.015 = 0.238
```

### Chutes 是否有 LLM 质量分？——明确：没有

| 问题 | 答案 |
|---|---|
| 是否对 LLM 输出内容打质量分？ | **否** |
| 是否用 Embedding 对比？ | **否** |
| 是否用 LLM-as-judge？ | **否** |
| cllmv 验证的是质量还是来源？ | **只验证来源**（来自声称的精确模型+版本） |

**为什么不评判内容质量？**

> "只要模型是真的，输出就是真实的——质量判断留给用户（市场）"

1. 开放式问题无客观正确答案，语义质量无法客观评判
2. 引入 LLM-as-judge 会带来新的中心化攻击面
3. 密码学证明比语义评估更可信、更 trustless
4. 用户举报机制兜底（被举报的调用不计分）

### 防作弊四层信任链

```
cllmv（逐 token hash）
  → 每个 token 与模型名+版本号密码学绑定
  → 证明：输出来自声称的精确模型

模型权重哈希（Watchtower 随机挑战）
  → 对模型文件随机偏移位哈希，验证器比对
  → 证明：矿工确实加载了真实模型权重，未偷换

GraVal GPU Proof
  → 在 GPU 上跑连续矩阵乘法，生成 AES-256 密钥
  → key = HMAC(GPU_UUID + timing_signature + nonce)
  → 所有推理流量用此密钥加密
  → 证明：运行在声称的真实 GPU 上（声称 A100 跑 A10 密钥不匹配）

Invocation 过滤（用户兜底）
  → 被举报的调用不计入评分
  → 矿工返回垃圾 → 用户报告 → 该调用不计分
```

类比：cllmv 就像酒瓶防伪码——**证明这是拉菲，但不评判好不好喝**。

---

## SN64 · Chutes 支持模型与价格

> 数据来源：chutes.ai 页面快照（2026-05-15）；跨平台对比来源：OpenRouter、DeepSeek 官方 API 文档、pricepertoken.com（OpenRouter 价格核查日期：2026-05-15）。OpenRouter 价格随市场频繁变动，以官网实时数据为准。  
> 价格单位：**美元 / 百万 tokens**。  
> 所有带 `-TEE` 后缀的模型运行在可信执行环境（TEE）中，提供密码学来源证明，为 Chutes 独有，其他平台无等价产品。

### LLM 模型定价（按 Chutes input 价格排序）

| 模型                                     | Chutes In | Chutes Out | OpenRouter In | OpenRouter Out |  官方 In | 官方 Out | 备注                                |
| -------------------------------------- | --------: | ---------: | ------------: | -------------: | -----: | -----: | --------------------------------- |
| Qwen/Qwen2.5-Coder-32B-Instruct-TEE    |    0.0245 |     0.0978 |         ~0.03 |          ~0.10 |  免费/低价 |  免费/低价 | 老模型，阿里云百炼基本不主推                    |
| Qwen/Qwen3-32B-TEE                     |      0.08 |       0.24 |          0.08 |           0.28 |  ~0.07 |  ~0.28 | OR 与官方基本接近                        |
| Qwen/Qwen3-235B-A22B-Thinking-2507     |      0.09 |       0.29 |         0.455 |           1.82 |  ~0.40 |  ~1.60 | Chutes 明显补贴                       |
| Qwen/Qwen3-Next-80B-A3B-Instruct-TEE   |    0.2989 |     1.1957 |             — |              — |  ~0.30 |  ~1.20 | 基本接近阿里云推测价                        |
| Qwen/Qwen3.5-397B-A17B-TEE             |      0.39 |       2.34 |          0.30 |           1.20 |   0.50 |   3.00 | 官方最贵；OR 较便宜 ([LLM Reference][1])  |
| Qwen/Qwen3.6-27B-TEE                   |      0.50 |       2.00 |             — |              — |      — |      — | 新模型，暂无公开价格                        |
| deepseek-ai/DeepSeek-V3-0324-TEE       |      0.25 |       1.00 |         ~0.27 |          ~1.00 |   0.27 |   1.10 | 已被 V3.2 取代                        |
| deepseek-ai/DeepSeek-V3.1-TEE          |      0.27 |       1.00 |          0.32 |           0.89 |  ~0.30 |  ~0.90 | V3.1 是过渡版本                        |
| deepseek-ai/DeepSeek-V3.2-TEE          |      0.28 |       0.42 |         0.252 |          0.378 |  0.252 |  0.378 | OR 与官方几乎一致 ([Price Per Token][2]) |
| deepseek-ai/DeepSeek-R1-0528-TEE       |      0.45 |       2.15 |          0.50 |           2.15 |   0.55 |   2.19 | Chutes input 略便宜                  |
| tngtech/DeepSeek-TNG-R1T2-Chimera-TEE  |      0.30 |       1.10 |             — |              — |      — |      — | 社区 finetune                       |
| moonshotai/Kimi-K2.5-TEE               |      0.44 |       2.00 |          0.44 |           2.00 |   0.44 |   2.00 | 三方价格统一                            |
| moonshotai/Kimi-K2.6-TEE               |      0.74 |       3.50 |          0.73 |           3.49 |   0.72 |   3.50 | 基本一致                              |
| zai-org/GLM-4.7-TEE                    |      0.39 |       1.75 |         ~0.50 |          ~2.00 |  ~0.60 |  ~2.40 | OR 略便宜                            |
| zai-org/GLM-5-Turbo                    |    0.4891 |     1.9565 |         ~0.70 |          ~2.80 |   1.20 |   4.00 | Chutes 补贴非常明显                     |
| zai-org/GLM-5-TEE                      |      0.95 |       2.55 |          0.60 |           1.92 |   0.60 |   1.92 | OR≈官方；Chutes 偏贵                   |
| zai-org/GLM-5.1-TEE                    |      1.05 |       3.50 |          0.98 |           3.08 |   0.95 |   3.00 | Chutes 略贵                         |
| unsloth/Mistral-Nemo-Instruct-2407-TEE |    0.0245 |     0.0978 |         ~0.03 |          ~0.10 |   开源免费 |   开源免费 | 老模型                               |
| XiaomiMiMo/MiMo-V2-Flash-TEE           |      0.09 |       0.29 |             — |              — |      — |      — | 小米新模型                             |
| MiniMaxAI/MiniMax-M2.5-TEE             |      0.15 |       1.20 |          0.15 |           1.20 |   0.15 |   1.20 | 三方统一                              |
| google/gemma-4-31B-turbo-TEE           |      0.13 |       0.38 |         ~0.10 |          ~0.40 | 免费（限速） | 免费（限速） | Google AI Studio 免费               |
| google/gemma-4-27B                     |         — |          — |         ~0.06 |          ~0.30 |     免费 |     免费 | Together/Fireworks 托管价            |

[1]: https://www.llmreference.com/model/qwen3.5-plus/openrouter?utm_source=chatgpt.com "Qwen3.5-Plus (qwen/qwen3.5-plus-20260420) Pricing on OpenRouter — LLMReference | LLM Reference"
[2]: https://pricepertoken.com/pricing-page/model/deepseek-deepseek-v3.2?utm_source=chatgpt.com "DeepSeek V3.2 API Pricing 2026 - Costs, Performance & Providers"


### 价格竞争力小结

| 结论 | 模型 |
|---|---|
| **Chutes 显著便宜** | Qwen3-235B-Thinking-2507（in ~40%↓，out ~80%↓）、GLM-5-Turbo |
| **与主流平台持平** | Qwen3-32B、DeepSeek-V3.2、DeepSeek-R1-0528、Kimi-K2.6 |
| **Chutes 略贵** | Kimi-K2.5（+10%）、MiniMax-M2.5（out +$0.05）、GLM-5、GLM-5.1、Qwen3.5-397B |
| **仅 Chutes 有 TEE 版** | 全部带 `-TEE` 后缀模型（密码学来源证明） |

### 版本新旧情况

以下模型在 Chutes 上线的版本已有更新替代，供参考：

| Chutes 上的版本 | 已发布的更新版 | 发布日期 |
|---|---|---|
| MiniMax-M2.5 | MiniMax-M2.7 | 2026-03-18 |
| DeepSeek-V3-0324 | DeepSeek-V3.2 | — |
| Mistral-Nemo-Instruct-2407 | Mistral 系列更新多代 | 2024 年后 |
| Qwen2.5-Coder-32B | Qwen3 系列全面取代 | 2025 年 |

---

## 两者核心对比

| 维度 | SN19 · Nineteen | SN64 · Chutes |
|---|---|---|
| **LLM 质量分** | 名义存在，实质是速度分 | 完全不存在 |
| **内容质量保证方式** | 不保证，评速度，靠市场筛选 | 密码学证明模型来源 |
| **核心评分依据** | TTFT + TPS + 响应成功率 | 7天 GPU 算力量 + 多样性 |
| **防作弊核心** | 不可预测种子 + 容量声明惩罚 | GraVal GPU Proof + Watchtower |
| **评分周期** | 每 60 分钟实时 | 7 天滚动窗口 |
| **Validator 门槛** | 标准质押（1000 stake-weight） | 极高，推荐 child hotkey |
| **最终排放结算** | Yuma Consensus，每 ~72 分钟 | Yuma Consensus，每 ~72 分钟 |

---

## 付费流程与链层参与

### 两套系统的关系

TAO 排放（激励）和服务收入（用户付费）是**两套独立系统，通过 Auto-staking Buyback 耦合**。

```
TAO 排放系统（链上）：
  Yuma Consensus → 每 360 区块 → 矿工 41% + 验证者 41% + 子网主 18%

服务收入系统（半链下）：
  用户付费 → 平台账户 → API 扣费（链下计量）

耦合机制：
  服务收入 → 购买 Alpha token（链上 AMM）→ Auto-staking → 子网权重↑ → TAO 排放↑
```

**当前排放 vs 收入比例：SN64 TAO 排放约 $52M/年，服务收入约 $1.3-2.4M/年，比例约 22:1–40:1。**（数据来源：Pine Analytics；$2.4M 为团队自报数字，未经独立审计；$52M 基于 SN64 占全网约 14.4% 排放份额估算）  
排放补贴远大于服务收入，是矿工的主要收益来源。

---

### SN64 Chutes 付费流程

**定价模式：** Per-token + Per-GPU-hour，Pay-as-you-go

**支付方式：**

| 方式 | 是否链上 | 说明 |
|---|---|---|
| TAO 充值 | **链上** | 转账到 Rayon Labs SS58 地址，有 tx hash，可在 taostats.io 查询 |
| SN64 Alpha token 充值 | **链上** | 同上 |
| Fiat（法币）充值 | **链下** | 第三方支付处理商，明细不在链上显示 |
| API 按使用扣费 | **链下** | 平台内部记账，不产生链上交易 |

**资金流向：**

```
用户
 ├─ TAO 充值 ──────────────────→ Rayon Labs SS58 地址 [链上]
 └─ Fiat 充值 ─────────────────→ 第三方支付商 [链下]
                                         │
                                  用户 USD 余额账户 [链下]
                                         │
                            按 per-token/GPU-hour 扣费 [链下计量]
                                         │
                               Rayon Labs 平台服务收入
                                         │
                               SN64 Alpha token Buyback
                                  [链上 AMM 操作]
                          │
               Alpha token Auto-staking [链上]
                          │
               SN64 子网权重↑ → 获得更多 TAO 排放
                          │
              ┌───────────┼───────────┐
              ↓           ↓           ↓
          矿工 41%    验证者 41%  Rayon Labs 18%
         (~$21M/年)  (~$21M/年)  (~$9.4M/年)   ← 按 $52M 排放估算，来源：Pine Analytics
```

**矿工不直接收取用户费用**，服务收入通过 Alpha Buyback → 提升排放份额 → 间接奖励矿工。

---

### SN19 Nineteen 付费流程

**访问方式：**
- **免费前端**（app.sn19.ai）：无需注册，无需 API key，直接使用
- **付费 API**：2025 年上线，面向开发者

**去中心化带宽销售（设计目标）：**  
官方 Roadmap：*"Validators can sell their organic traffic in a completely decentralised way"*  
各 Validator 自己运行 API Server，理论上可自主定价收款，收入不流经 Rayon Labs。

**实际状态：**
- 服务收入**未公开披露**（Pine Analytics 确认"no disclosed revenue"）
- 主要依靠 TAO 排放（占总排放约 2.71%，来源：[ChainUp 2025-06](https://www.chainup.com/market-update/bittensor-the-ai-alpha/)）
- 付费 API 的收款方和资金流向暂无公开文档，无法确认

---

### 链层参与程度汇总

| 操作 | 链上？ | 说明 |
|---|---|---|
| 用户 TAO 充值 | **是** | SS58 转账，链上可查 |
| API 使用计量扣费 | **否** | 平台内部账本 |
| Fiat 充值 | **否** | 法币通道 |
| Alpha token Buyback | **是** | AMM 操作，链上可追踪 |
| Auto-staking | **是** | 链上质押 |
| TAO 排放分发 | **是** | Yuma Consensus 每 ~72 分钟结算 |

**结论：入金可以走链，日常计量完全链下，出金（矿工获得排放）走链。**  
用户付费本质上是「链上入金 → 链下计量 → 链上 Buyback 出金」的混合模式。

---

## 延伸思考

**SN19 的局限**：速度即质量的假设在高质量推理场景下存在问题——更快的硬件天然占优，而不是更好的模型或推理策略。

**SN64 的局限**：完全不评判输出质量，意味着劣质模型（只要是"真"的）也能获得和优质模型相同的算力奖励。内容质量完全依赖用户市场自净。

**行业趋势**：如何在去中心化网络中客观评判 LLM 输出质量，是 Bittensor 生态面临的核心未解问题。


---

## 借鉴价值（研究视角）

> 详细分析见 `chutes-analysis.md`，此处提炼核心洞察。

### 1. Goodhart's Law 与激励机制设计

SN19 和 SN64 都不对 LLM 输出做语义评分，原因相同：一旦语义相似度变成评分目标，矿工会优化"和参考答案像不像"而非"回答质量"，导致轻量保守模型占优，网络质量反向劣化。

**设计评分机制时，可代理指标（proxy metric）的选择至关重要。** 错误的 proxy 会让参与者绕过真正的目标，直接优化指标本身。

### 2. "证明来源 vs 评判质量"的二元选择

SN64 的解法：将质量评判完全外包给市场，只做密码学来源证明。在无法建立客观评分标准的场景（开放式生成任务），这是务实的妥协——不强行量化无法量化的东西，但代价是内容质量完全依赖用户自净。

**对比两种哲学的适用场景：**

| 场景 | 推荐方案 | 代表 |
|---|---|---|
| 延迟敏感，质量可替代 | 速度代理质量（SN19 模式） | 聊天、补全类推理 |
| 来源可信度有要求（合规/审计） | 密码学证明来源（SN64 模式） | 企业级、金融、医疗 |
| 有客观评分标准 | 直接质量评分 | 代码评测、数学推理 |

### 3. 多样性激励的非对称惩罚

低于中位数用更陡的惩罚指数（2.2），高于中位数用温和增益（1.3）。**非对称设计有效防止网络同质化，同时不过度惩罚头部。** 可推广到任何需要鼓励生态多样性的激励系统。

### 4. 排放补贴模式的局限

两个子网的矿工主要收益来自 TAO 排放，而非用户付费（SN64 约 22:1）。排放驱动能有效引导初期资源投入，但长期需要服务收入增长承接，否则矿工行为与用户价值脱钩，网络进入补贴依赖的脆弱状态。

---


## 参考资料

- [SN19 官方文档](https://sn19.ai/docs/about)
- [Chutes 评分文档](https://chutes.ai/docs/miner-resources/scoring)
- [Chutes 安全架构文档](https://chutes.ai/docs/core-concepts/security-architecture)
- [Chutes cllmv 可信计算博客](https://chutes.ai/news/confidential-compute-for-ai-inference-how-chutes-delivers-verifiable-privacy-with-trusted-execution-environments)
- [namoray/nineteen · GitHub](https://github.com/namoray/nineteen)
- [rayonlabs/chutes-api · GitHub](https://github.com/rayonlabs/chutes-api)
- [rayonlabs/chutes-audit · GitHub](https://github.com/rayonlabs/chutes-audit)
- [Rayon Labs: The Subnet Trifecta · Messari](https://messari.io/report/rayon-labs-the-subnet-trifecta)
- [NineteenAI (SN19) · Asymmetric Jump](https://asymmetricjump.substack.com/p/nineteenai-subnet-19-bittensor)
- [Chutes (SN64) · Asymmetric Jump](https://asymmetricjump.substack.com/p/bittensor-subnet-research-chutes)
- [Bittensor 激励机制文档](https://docs.learnbittensor.org/learn/anatomy-of-incentive-mechanism)
- [Chutes 模型列表](https://chutes.ai/app)（页面快照 2026-05-15）
- [OpenRouter 定价](https://openrouter.ai/pricing)
- [Google Gemma 4 定价（第三方）](https://pricepertoken.com/pricing-page/model/google-gemma-4-26b-a4b-it)
- [Google AI Studio 定价](https://ai.google.dev/gemini-api/docs/pricing)
- [DeepSeek API 定价](https://api-docs.deepseek.com/quick_start/pricing/)
- [DeepSeek V3.2 · OpenRouter](https://openrouter.ai/deepseek/deepseek-v3.2)
- [DeepSeek R1-0528 · OpenRouter](https://openrouter.ai/deepseek/deepseek-r1-0528)
- [Qwen3-32B · OpenRouter](https://openrouter.ai/qwen/qwen3-32b)
- [Qwen3-235B-A22B · OpenRouter](https://openrouter.ai/qwen/qwen3-235b-a22b)
- [Kimi K2.5 · OpenRouter](https://openrouter.ai/moonshotai/kimi-k2.5)
- [Kimi K2.6 · OpenRouter](https://openrouter.ai/moonshotai/kimi-k2.6)
- [GLM-5 · OpenRouter](https://openrouter.ai/z-ai/glm-5)
- [GLM-5.1 · OpenRouter](https://openrouter.ai/z-ai/glm-5.1)
- [MiniMax M2.7 定价](https://pricepertoken.com/pricing-page/model/minimax-minimax-m2.7)
- [Bittensor Income Desert · CryptoNews](https://cryptonews.com/news/bittensor-income-desert-tao-valuation-risk/)（Pine Analytics 数据来源）

