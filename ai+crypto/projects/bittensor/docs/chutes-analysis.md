# SN64 Chutes 深度研究

> 研究日期：2026-05-22
> 定位：Bittensor 系列续集，研究视角，关注机制设计与借鉴价值
> 前置阅读：`sn19-sn64-scoring.md`（评分机制与收费流程详解）

---

## 1. 定位

SN64 Chutes 是 Bittensor 生态第 64 号子网，由 Rayon Labs 开发（同一团队也开发了 SN19 Nineteen AI）。

**核心定位：去中心化无服务器 AI 算力平台**

关键概念：**Chute = 一个 Docker 容器化的 AI 应用**，包含模型 + 推理服务。矿工注册 GPU 硬件，部署 Chute（启动容器），开发者通过标准 OpenAI 兼容 API 发送请求，Validator 负责路由和结算。

### 与 SN19 Nineteen AI 的区别

| | SN19 | SN64 |
|---|---|---|
| 定位 | 推理加速网络 | 通用 AI 算力市场 |
| 核心哲学 | **快 = 好**（速度即质量） | **真实 = 可信**（密码学保证来源） |
| 支持 workload | LLM 文本 + 图像生成（固定类型） | 任意 AI workload（LLM、图像、embedding、自定义模型） |
| 评分核心 | 响应速度（TTFT/TPS） | 算力贡献量（GPU-hours） |
| 对质量的态度 | 不做语义评分，速度代理质量 | 不做语义评分，密码学证明来源 |

### 与中心化平台的区别

| | OpenAI / Together / OpenRouter | Chutes |
|---|---|---|
| 信任基础 | 相信平台声称用了哪个模型 | 密码学证明运行了声称的精确模型权重，在声称的 GPU 上 |
| 定价 | 平台定价，不透明 | 矿工竞争，部分模型显著低于市场价 |
| 隐私 | 平台可见推理内容 | TEE 模型：即使矿工也看不到 |

---

## 2. 核心创新

Chutes 最值得关注的是其**四层叠加信任链**，从"输出内容"到"模型权重"到"硬件"到"计算过程"逐层验证。

### Layer 1：cllmv（Confidential LLM Verification）——输出来源证明

逐 token hash 验证。推理过程中，每个输出 token 与模型名 + 版本号 + nonce 做密码学绑定，形成可验证的 hash 链。

```
for each output_token:
    hash = HMAC(token | model_name | model_version | nonce)
→ Validator 可验证：输出确实来自"deepseek-ai/DeepSeek-V3.2"这个精确版本
```

- **证明**：这个输出来自声称的精确模型，而非量化版、裁剪版或其他模型冒充
- **不证明**：输出质量好不好
- **类比**：酒瓶防伪码——证明是拉菲，不评判好不好喝

### Layer 2：Watchtower 模型权重挑战——权重真实性证明

Validator 随机向矿工发起挑战：对模型文件某个随机偏移位计算 hash，比对预期值。

```
Validator → 矿工: "给我模型文件 offset=1,048,576 处的 hash"
矿工 → Validator: hash_value
Validator: 比对预期值，不匹配 → 判定权重不真实
```

- **证明**：矿工确实在内存中加载了完整真实权重，无法用空壳或不同模型欺骗
- 随机挑战确保矿工无法提前缓存答案

### Layer 3：GraVal GPU Proof——硬件真实性证明

用时序敏感的连续矩阵乘法生成与 GPU 绑定的密钥：

```
在声称的 GPU 上跑特定连续矩阵乘法（对 GPU 型号的时序特征敏感）
  → 生成时序签名
  → key = HMAC(GPU_UUID + timing_signature + nonce)
  → 所有推理流量用此密钥加密
```

- 声称 A100 但实际跑 A10：时序特征不匹配，密钥无法通过 Validator 验证
- **证明**：运行在声称的真实 GPU 型号上，不依赖 TEE 硬件，普通 GPU 即可
- 矿工无法伪造：不同 GPU 的矩阵乘法时序特征是硬件固有特性

### Layer 4：TEE 推理（Trusted Execution Environment）——计算过程不可篡改

部分模型（带 `-TEE` 后缀）运行在 Intel SGX / AMD SEV 等硬件隔离区：

- 即使矿工操控宿主机，也无法访问或篡改 TEE 内的推理过程
- 推理结果可附带 TEE attestation，供调用方独立验证
- 这是目前 Chutes 独有的能力，其他平台（OpenRouter 等）没有等价产品

**四层信任链叠加总结：**

```
cllmv          → 证明：输出来自声称的精确模型版本
Watchtower     → 证明：矿工加载了真实完整模型权重
GraVal         → 证明：运行在声称的真实 GPU 型号上
TEE            → 证明：计算过程本身不可被矿工篡改
```

---

## 3. 机制设计洞察

### 3.1 为什么 LLM 评分不能用语义质量？——Goodhart's Law

**Goodhart's Law**：当一个指标变成目标，它就不再是好指标。

假设用语义相似度对矿工输出评分（用 Validator 自己的模型生成"参考答案"，对比矿工回答的 embedding 余弦相似度）：

| | 输出风格 | 与参考答案相似度 |
|---|---|---|
| 小模型 7B | 公式化、保守，贴近最主流答案 | **高**（紧贴平均答案） |
| 大模型 70B | 有深度，补充细节，提出非预期角度 | **低**（语义发散） |

- 大模型给出更有价值的回答，却因"偏离参考答案"而得低分
- 矿工最优策略：用最小最快、输出最保守的模型——省成本、得高分
- 结果：网络里全是平庸轻量模型，网络失去价值

**Chutes 的解法**："证明来源，不评判质量"——质量判断留给用户（市场）。

这是一种务实妥协：在无法建立客观评分标准的场景（开放式生成任务），与其用坏指标触发 Goodhart's Law，不如放弃评判，改为验证可信度，让用户用脚投票。

### 3.2 评分权重的激励逻辑

```python
final_score = 0.55 × compute_units      # GPU 算力时间（速度隐含其中）
            + 0.15 × diversity_score     # 部署模型种类数
            + 0.05 × bounty             # 首个成功处理新 Chute 的奖励
            + ~0.25 × invocation_count  # 被调用次数（官方未公开权重）
```

| 指标 | 权重 | 激励行为 | 设计意图 |
|---|---|---|---|
| Compute Units | 55% | 跑更多 GPU 时间，处理更多请求 | 保证算力供给充足 |
| Chute 多样性 | 15% | 部署更多不同模型 | 防止网络同质化，增加模型覆盖 |
| Bounty（首发）| 5% | 快速响应新模型上线 | 激励网络快速扩展新能力 |
| Invocation Count | ~25% | 保持高可用性 | 奖励真实被用到的算力 |

**多样性的非对称惩罚设计：**

```python
if chute_count >= median:
    raw = (chute_count / max_count) ** 1.3   # 温和增益
else:
    raw = (chute_count / max_count) ** 2.2   # 陡峭惩罚（指数更大）
```

低于中位数的矿工用更陡的惩罚曲线，高于中位数用温和增益曲线。非对称设计有效防止矿工只跑单一热门模型，同时不过度惩罚头部多样性矿工。

### 3.3 防多号刷分

同一 coldkey 下多个 hotkey 参与，只保留最高分，其余归零。使得多号操作无法叠加收益，消除 sybil attack 动机。

---

## 4. 经济可持续性分析

### 4.1 双层收入结构

| 系统 | 金额估算 | 机制 |
|---|---|---|
| **TAO 排放**（链上激励） | ~$52M/年 | SN64 占全网约 14.4% 排放份额，按当前 TAO 价格估算 |
| **服务收入**（用户付费） | ~$1.3-2.4M/年 | Per-token / Per-GPU-hour，链下计量 |

> 数据来源：Pine Analytics；$2.4M 为 Rayon Labs 自报，未经独立审计；$52M 基于排放份额估算

**排放 vs 收入比例：22:1 ~ 40:1**——矿工真实收益主要来自 TAO 发行，而非用户付费。

### 4.2 耦合飞轮机制

服务收入不是直接分给矿工，而是通过 Alpha Buyback 耦合到链上激励：

```
用户付费
  → Rayon Labs 平台服务收入
  → 购买 SN64 Alpha token（链上 AMM）
  → Auto-staking 到子网
  → SN64 权重↑ → 获得更多 TAO 排放
  → 矿工 41% + 验证者 41% + Rayon Labs 18%
```

理论上优雅：真实服务价值会自动转化为更多排放，形成正向飞轮。

### 4.3 价格竞争力

部分模型 Chutes 显著低于中心化平台，可能源于排放补贴：

| 结论 | 代表模型 |
|---|---|
| **Chutes 显著便宜** | Qwen3-235B-Thinking-2507（input 便宜 ~40%，output 便宜 ~80%）、GLM-5-Turbo（便宜约 70%）|
| **与主流平台持平** | Qwen3-32B、DeepSeek-V3.2、DeepSeek-R1-0528、Kimi-K2.6 |
| **Chutes 略贵** | Kimi-K2.5、GLM-5、GLM-5.1、Qwen3.5-397B |
| **仅 Chutes 有** | 全部 -TEE 后缀模型（密码学来源证明） |

### 4.4 可持续性问题

当前模式本质是：**"TAO 排放补贴 AI 计算市场"**

风险路径：
```
TAO 价格下跌
  → 矿工 GPU 成本无法覆盖排放收益
  → 矿工退出，算力下降
  → 服务质量下降，用户流失
  → 服务收入减少，Alpha Buyback 减少
  → SN64 排放权重下降
  → 进一步压低矿工收益（螺旋）
```

**飞轮要正向运转，需要服务收入持续增长，逐步减少对排放的依赖。** 当前 22:1 的比例意味着商业化仍处于早期，排放补贴是维持供给的核心手段。

---

## 5. 借鉴价值

### 可借鉴的机制

**① "证明来源，不评判质量"的设计哲学**

适用场景：任何无法客观量化输出质量的 AI 服务。  
与其强行引入 proxy metric（触发 Goodhart's Law 风险），不如退而验证可信度，将质量评判交给市场/用户。  
特别适合：开放式生成任务、多模态输出、无标准答案的推理任务。

**② GraVal 类似的轻量硬件证明**

用时序敏感的计算任务生成与硬件绑定的密钥，是一种不依赖 TEE 的"硬件证明"方案。  
可推广到：任何去中心化计算网络的矿工硬件真实性验证，成本低，无需特殊硬件。

**③ 多样性分数 + 非对称惩罚曲线**

在任何需要鼓励生态多样性的激励系统中：低于中位数用更陡的惩罚指数，高于中位数用温和增益。  
有效防止同质化而不过度惩罚头部，可直接用于其他 AI 服务网络、内容平台、节点激励设计。

**④ Bounty（首发奖励）+ 几何衰减**

给第一个支持新能力的参与者额外奖励，带几何衰减（同一 chute 后续价值递减，避免长期占用）。  
低成本激励网络快速扩展能力覆盖，可用于任何需要"抢先部署新资源"激励的系统。

**⑤ 排放与服务收入的 Buyback 耦合**

将服务收入自动转化为网络权重（而非直接分配），让商业价值增强链上激励，形成飞轮。  
在有代币经济的网络中，比直接分钱更能持续拉动网络价值。但需要服务收入达到一定规模才有意义。

### 不适合直接借鉴（crypto 特有依赖）

- **Yuma Consensus** 整体依赖 TAO 质押，无法脱离 Bittensor 生态独立使用
- **Alpha token AMM** 依赖链上流动性，需要足够 TAO 持有者参与才有效
- **排放补贴模式** 需要代币持续增发，在非 crypto 场景下不适用——"补贴用户"换成"股权稀释"，逻辑不成立

---

## 参考资料

- [Chutes 官网](https://chutes.ai)
- [Chutes 评分文档](https://chutes.ai/docs/miner-resources/scoring)
- [Chutes 安全架构文档](https://chutes.ai/docs/core-concepts/security-architecture)
- [rayonlabs/chutes-api · GitHub](https://github.com/rayonlabs/chutes-api)
- [rayonlabs/chutes-audit · GitHub](https://github.com/rayonlabs/chutes-audit)
- [Rayon Labs: The Subnet Trifecta · Messari](https://messari.io/report/rayon-labs-the-subnet-trifecta)
- [Chutes (SN64) · Asymmetric Jump](https://asymmetricjump.substack.com/p/bittensor-subnet-research-chutes)
- `sn19-sn64-scoring.md`（本项目，评分与付费流程详解）
