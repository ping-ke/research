# Bittensor 技术分享

---

## 目录

1. [Bittensor 是什么？解决什么问题？](#1-bittensor-是什么解决什么问题)
2. [网络架构](#2-网络架构)
3. [核心流程](#3-核心流程)
4. [Yuma Consensus](#4-yuma-consensus)
5. [经济学（dTAO）](#5-经济学dtao)
6. [SDK 接口](#6-sdk-接口)
7. [真实案例：Covenant-72B（SN3 Templar）](#7-真实案例covenant-72bsn3-templar)
8. [挑战与风险](#8-挑战与风险)
9. [参考链接](#参考链接)

---

## 1. Bittensor 是什么？解决什么问题？

### 核心定位

Bittensor 是一个**去中心化 AI 网络**，核心目标是创建一个开放的、激励驱动的 AI 智能市场。与传统的去中心化计算网络（如 Akash、Render）不同，Bittensor 不仅仅出租 GPU 算力，而是**评估 AI 输出的质量**并奖励产出最优智能的参与者。

> 核心愿景：让 AI 模型的训练和推理去中心化，通过经济激励让全球参与者协作构建更好的 AI。
>
> 类比：比特币激励全球矿工维护账本；Bittensor 激励全球 GPU 节点竞争产出最优智能。

![bittensor subnet](./images/bittensor-subnets.png)

### 和以太坊的区别

| 维度 | 以太坊 | Bittensor |
|------|--------|-----------|
| **解决的问题** | 去中心化通用计算（智能合约） | 去中心化 AI 能力市场 |
| **节点工作** | 执行 EVM 字节码，验证交易 | 运行 AI 模型，竞争产出最优输出 |
| **共识目标** | 对"状态转移"达成一致 | 对"AI 输出质量"达成一致 |
| **激励对象** | 区块验证者（质押 ETH） | AI Validator/Miner（质量越高收益越多）|
| **链技术** | EVM / Solidity | Substrate / Rust |
| **可组合性** | 任意合约互调 | 子网独立，各自定义 AI 任务 |

**关键差异**：以太坊验证"计算是否正确执行"，Bittensor 评估"AI 输出质量是否最优"——后者本质是一个**链上 AI 质量排名系统**。

---

## 2. 网络架构

### 三层结构

![how bittensor actually work](./images/how-bittensor-actually-work.png)

```
┌─────────────────────────────────────────────────────────┐
│                 Subtensor（区块链层）                    │
│   Substrate / Rust，出块 ~12s                            │
│   负责：注册、质押、Yuma Consensus、emission 分配         │
├───────────┬───────────┬───────────┬─────────────────────┤
│ Subnet 19 │ Subnet 64 │ Subnet 3  │     Subnet N        │
│ LLM 推理  │ 无服务器   │ 分布式     │     ...             │
│(Nineteen) │ AI 计算   │  训练      │  127 个子网         │
├───────────┴───────────┴───────────┴─────────────────────┤
│       每个子网：Miners（执行）+ Validators（评分）        │
└─────────────────────────────────────────────────────────┘
```

### 角色

| 角色 | 职责 | 收益 |
|------|------|------|
| **Miner** | 运行 AI 任务（推理/训练），通过 Axon 暴露服务 | 按输出质量获得 Alpha emission（41%）|
| **Validator** | 查询 Miner，评估质量，提交权重上链 | 按 Bond 积累获得 Alpha emission（41%）|
| **Subnet Owner** | 定义任务规则，维护子网 | 固定 18% Alpha emission |

### 神经科学隐喻（SDK 命名来源）

| 术语 | 对应概念 |
|------|---------|
| **Axon** | Miner 的服务端点（监听端口） |
| **Dendrite** | Validator 的请求客户端 |
| **Synapse** | 请求/响应的消息结构体 |
| **Metagraph** | 子网所有节点状态的链上快照 |

> 查看 SN3 当前活跃 Miner：[taostats.io/subnets/3/metagraph](https://taostats.io/subnets/3/metagraph) → Metagraph 标签页
>
> 或用命令行：
> ```bash
> btcli subnet metagraph --netuid 3
> ```
---

## 3. 核心流程


### Subnet 内 Miner-Validator 交互流程

> 以 SN3 (Templar) 为例：Miner 提交训练好的模型梯度，Validator 评估训练贡献质量

```mermaid
sequenceDiagram
    participant V as Validator
    participant Chain as Subtensor Chain
    participant M1 as Miner 1 (GPU Node)
    participant M2 as Miner 2 (GPU Node)
    participant M3 as Miner 3 (GPU Node)

    V->>Chain: 读取 Metagraph（获取已注册 Miner 列表）
    Chain-->>V: Miner UIDs, Axon 端点, 质押信息

    par 并行查询所有 Miner
        V->>M1: Dendrite.query(Synapse)
        V->>M2: Dendrite.query(Synapse)
        V->>M3: Dendrite.query(Synapse)
    end

    M1-->>V: Response（质量高）
    M2-->>V: Response（质量中）
    M3-->>V: Response（超时/低质量）

    V->>V: 评分: reward(responses) → [0.8, 0.5, 0.0]
    V->>Chain: set_weights(uids=[1,2,3], weights=[0.8, 0.5, 0.0])

    Note over Chain: Yuma Consensus 聚合所有 Validator 的权重
    Chain->>Chain: 计算 incentive + dividend
    Chain->>M1: Emission（最多）
    Chain->>M2: Emission（较少）
    Chain->>V: Dividend（基于 bond）
```

### dTAO 质押与 Emission 流程

> Emission 是**两阶段**过程：先是每个 block 的 **Injection**（注入流动性到子网池），再是每个 tempo (~360 blocks) 的 **Distribution**（分配给参与者）

```mermaid
sequenceDiagram
    participant S as Staker
    participant Pool as Subnet AMM Pool<br/>(TAO Reserve / Alpha Reserve)
    participant Sub as Subtensor Chain
    participant AO as Alpha Outstanding<br/>(待分配池)
    participant Owner as Subnet Owner
    participant V as Validators + Stakers
    participant M as Miners

    Note over S,Pool: === 质押 ===
    S->>Pool: 质押 TAO
    Pool->>Pool: TAO 进入 TAO Reserve<br/>Alpha 从 Alpha Reserve 取出
    Pool-->>S: 返回 Alpha Token

    Note over Sub,AO: === 每个 Block: Injection 阶段 ===
    Sub->>Sub: 产出 0.5 TAO（halving 后）
    Sub->>Sub: 按各子网 net TAO flow<br/>EMA 计算 emission share

    rect rgb(240, 248, 255)
        Note over Pool,AO: 三路注入（保持 alpha 价格不变）
        Sub->>Pool: ① TAO 注入 TAO Reserve<br/>(Δτᵢ = 0.5 × shareᵢ)
        Sub->>Pool: ② Alpha 注入 Alpha Reserve<br/>(Δαᵢ = Δτᵢ / price，维持价格)
        Sub->>AO: ③ Alpha 注入 Outstanding<br/>(= alpha emission rate，上限 1/block)
    end

    Note over AO,M: === 每个 Tempo (~72min): Distribution 阶段 ===
    rect rgb(255, 248, 240)
        Note over AO: 累积的 Alpha Outstanding<br/>按比例分配：
        AO->>Owner: 18% → Subnet Owner
        AO->>M: 41% → Miners<br/>(按 Yuma Consensus Incentive 分配)
        AO->>V: 41% → Validators & Stakers<br/>(按 Yuma Consensus Dividends 分配)
    end

    Note over V: Validator 的 alpha 收益中<br/>一部分通过 Pool swap 为 TAO<br/>发给 TAO 质押者

    Note over S,Pool: === 取消质押 ===
    S->>Pool: 归还 Alpha Token
    Pool-->>S: 返回 TAO（按当前汇率，有滑点）
```

### Emission 注入的关键细节

**Q: 每个 block 产出的 0.5 TAO 如何在子网间分配？**

当前使用 **Flow-Based Model**（2025.11 上线，替代了之前的 price-based model）：

```
1. 跟踪每个子网的 net TAO flow：
   net_flow = Σ(TAO staked) - Σ(TAO unstaked)

2. 计算 EMA（86.8 天窗口，30 天半衰期）：
   S_i = (1-α) × S_{i-1} + α × net_flow_i    (α ≈ 0.000003209)

3. 计算动态下界 L（相对基准）：
   L = max(FlowCutoff, min_j( min(S_j, 0) ))
   │   └─ 治理参数，防止 L 过低   └─ 所有子网 EMA 中最负的那个（正值取 0）

4. 裁剪 + 归一化：
   z_i = max(S_i - L, 0)
   share_i = z_i / Σ z_j         （线性分配）

   作用：把最差子网的 z_i 归零，其余子网按相对优势分配 emission

4. 最终注入：
   Δτ_i = 0.5 TAO × share_i
```

→ **净流入多的子网获得更多 emission**；净流出的子网 emission 为零

**Q: 注入到子网池后发生什么？三路注入保持价格不变**

```
子网 i 每个 block 的注入：

① TAO Reserve += Δτ_i         （TAO 储备增加）
② Alpha Reserve += Δτ_i / p_i  （Alpha 储备按价格比例增加，保持价格 p_i 不变）
③ Alpha Outstanding += min(Δτ̄/Σp_j, 1)  （待分配的 Alpha，上限 1/block）
```

- ① 和 ② 增加池的流动性（降低交易滑点），但**不改变 alpha 价格**
- ③ 是真正要分给参与者的 Alpha

**Q: Miner 和 Validator 收到的是 Alpha 还是 TAO？**

```
每个 tempo (~360 blocks) 结算：

Alpha Outstanding 累积量按比例分配：
├── 18% → Subnet Owner（收到 Alpha）
├── 41% → Miners（收到 Alpha，按 Incentive 分配）
└── 41% → Validators & Stakers
    ├── Validator 抽取佣金（Alpha）
    └── 剩余分给 Stakers：
        ├── Alpha Stakers → 收到 Alpha
        └── TAO Stakers → Alpha 通过池 swap 为 TAO 后发放
```

![bittensor feedback loop](./images/bittensor-feedback-loop.png)

**核心回答：Miner 和 Validator 直接收到的是子网的 Alpha Token，不是 TAO。** TAO Staker 的收益会通过 AMM 池自动 swap 为 TAO。

### Subnet 生命周期

```mermaid
flowchart LR
    A[创建 Subnet<br/>burn TAO] --> B[定义协议<br/>Synapse schema]
    B --> C[部署 Miner<br/>注册 + 运行 Axon]
    C --> D[部署 Validator<br/>查询 + 评分 + set_weights]
    D --> E[Yuma Consensus<br/>链上聚合权重]
    E --> F[Emission 分配<br/>Miner/Validator/Owner]
    F --> G{dTAO 市场反馈}
    G -->|alpha 价格上升<br/>更多 emission| D
    G -->|alpha 价格下降<br/>emission 减少| H[Subnet 萎缩/退出/卖出]
```

---

## 4. Yuma Consensus

**核心问题**：Validator 互相勾结给自己 Miner 打高分怎么办？

### 算法

```
输入：权重矩阵 W[i][j]（Validator i 对 Miner j 的评分）

1. 质押加权
   每个 Validator 的权重按其质押量 S[i] 缩放

2. 共识向量（加权中位数，非均值）
   C[j] = weighted_median({ W[i][j] }, weights={ S[i] })

3. 共识裁剪（Clipping）
   W̃[i][j] = min(W[i][j], C[j])
   偏离共识的权重被压低，偷分失效

4. Rank & Incentive（决定 Miner emission）
   R[j] = Σᵢ S[i] × W̃[i][j]
   I[j] = R[j] / Σₖ R[k]   ← 归一化

5. Bond & Dividends（决定 Validator emission）
   B[i][j] = EMA(ΔB[i][j])     ← 长期关系积累
   D[i]    = Σⱼ B[i][j] × I[j] ← 分享 Miner 的收益

6. Trust（衡量评分诚实度）
   T[j] = R[j] / R_pre_clip[j]  ← 接近 1.0 = 与共识一致
```

**防勾结机制**：
- 中位数而非均值 → 少数大户操纵无效
- Bond EMA → 激励 Validator 长期稳定评分，频繁切换者收益少
- Clipping → 偏离共识者影响力被截断

---

## 5. 经济学（dTAO）

### TAO 基本参数

| 参数 | 值 |
|------|-----|
| 最大供应量 | 21,000,000 TAO（同 BTC）|
| 出块时间 | ~12 秒 |
| 当前区块奖励 | **0.5 TAO**（2025.12 首次 halving 后）|
| 每日 emission | ~3,600 TAO/天 |

### 每个子网的 AMM 池

每个子网有独立的 Alpha Token 和恒定乘积 AMM 池（类似 Uniswap，无手续费）：

```
质押 TAO   → TAO 进 TAO Reserve，Alpha 从 Alpha Reserve 取出 → 用户得 Alpha
取消质押   → 归还 Alpha → TAO 从 TAO Reserve 取出 → 用户得 TAO（有滑点）

Alpha 价格 = TAO Reserve / Alpha Reserve
```

### 质押 TAO = 为子网"投票"

```
子网 emission 份额 ∝ 净 TAO 流入的 EMA（86.8 天窗口）

净流入多 → 获得更多 emission → Alpha 预期上涨
净流出   → emission 归零   → Alpha 卖压增大
```

市场机制：emission 自动流向最受资金认可的子网，无需人工治理。

### Alpha 价格为什么普遍很低？

Miner/Validator 收到 Alpha 后**持续通过 AMM 卖回 TAO**（换成稳定收益）→ 形成持续卖压。

Alpha 价格反映的是「**市场对该子网未来净流入的预期**」，而非当前质押量。

**典型数据（Subnet 1）：**

```
TAO Reserve:   657 τ   Alpha Reserve: 161k α
Alpha 价格:    0.0004 τ/α（1 TAO ≈ 2500 Alpha）
EMA 净流入:    -0.0338（净流出 → emission 为零）
```


---

## 6. SDK 接口

> 模板仓库：[github.com/latent-to/bittensor-subnet-template](https://github.com/latent-to/bittensor-subnet-template)

### 安装

```bash
pip install bittensor bittensor-cli torch
# 验证安装
btcli --version
```

### 三个核心文件
```
bittensor-subnet-template/
├── neurons/
│   ├── miner.py       ← 实现 forward()，处理 Validator 的请求
│   └── validator.py   ← 查询 Miner，打分，set_weights()
└── template/
    └── protocol.py    ← 定义 Synapse（请求/响应结构）
```

### Step 1：定义协议（Synapse）

```python
import bittensor as bt

class MyProtocol(bt.Synapse):
    query: str            # Validator 发送的输入
    response: str = ""    # Miner 填充后返回
```

### Step 2：Miner 实现

```python
# miner.py
def forward(synapse: MyProtocol) -> MyProtocol:
    synapse.response = my_model.generate(synapse.query)
    return synapse

wallet    = bt.Wallet(name="miner", hotkey="h1")
subtensor = bt.Subtensor(network="finney")
axon      = bt.Axon(wallet=wallet, port=8091)
axon.attach(forward_fn=forward)
axon.serve(netuid=NETUID, subtensor=subtensor)
axon.start()
```

### Step 3：Validator 实现

```python
# validator.py
import torch

wallet    = bt.Wallet(name="validator", hotkey="h1")
subtensor = bt.Subtensor(network="finney")
dendrite  = bt.dendrite(wallet=wallet)
metagraph = subtensor.metagraph(netuid=NETUID)

# 查询所有 Miner
responses = dendrite.query(
    axons=metagraph.axons,
    synapse=MyProtocol(query="Hello"),
    timeout=12.0
)

# 打分（自定义逻辑）
scores = torch.tensor([1.0 if r.response else 0.0 for r in responses])
weights = scores / scores.sum()

# 写入链上
subtensor.set_weights(
    netuid=NETUID,
    uids=metagraph.uids,
    weights=weights,
    wallet=wallet
)
```

### Step 4：注册并运行

```bash
btcli subnet register --netuid <NETUID> --wallet.name miner --wallet.hotkey h1
python neurons/miner.py     --netuid <NETUID> --wallet.name miner
python neurons/validator.py --netuid <NETUID> --wallet.name validator
```

### 常用 btcli 命令

```bash
btcli subnet list                         # 查看所有子网
btcli subnets metagraph --netuid 19       # 查看 SN19 节点状态
btcli wallet overview                     # 查看余额/质押
btcli stake add --netuid 19 --amount 10   # 质押 TAO 到 SN19
```

---

## 7. 真实案例：Covenant-72B（SN3 Templar）

SN3 (Templar) 于 2026 年 3 月完成史上最大去中心化 LLM 预训练：

| 指标 | 数值 |
|------|------|
| 参数量 | **72B** |
| 训练数据 | ~1.1 万亿 token |
| 参与节点 | **70+，无许可** |
| MMLU 得分 | **67.1**（对标 Llama-2-70B）|
| 基础设施 | 普通商用互联网，无数据中心 |

**技术关键 —— SparseLoCo**：本地迭代 15–250 步后，只同步 1–3% 核心梯度（量化为 2-bit，压缩率 97%），通过 S3/R2 对象存储异步交换。解决了去中心化训练的带宽瓶颈。

**市场反应**：SN3 alpha token 一月内涨 444%，黄仁勋称其为"现代版 Folding@home"。

### 核心技术：SparseLoCo 算法

去中心化训练的最大瓶颈是**带宽**。传统分布式训练（如 PyTorch DDP）需要在每步同步完整梯度，但跨互联网的带宽远低于数据中心内部。

SparseLoCo 的解决方案：
```mermaid
flowchart TB
    subgraph 传统分布式训练
        A1[节点 A: 计算梯度] --> B1[同步完整梯度<br/>每步都同步<br/>需高带宽]
        B1 --> C1[节点 B: 接收更新]
    end
    subgraph SparseLoCo
        A2[节点 A: 本地迭代<br/>15-250 步] --> B2[选择 1-3% 核心梯度<br/>量化为 2-bit<br/>压缩率 97%]
        B2 --> C2[通过对象存储<br/>异步交换伪梯度]
        C2 --> D2[节点 B: 合并更新]
    end
```

关键创新点：
1. **稀疏选择**：只传输 1%-3% 的核心梯度分量
2. **极端量化**：将数据量化为 2-bit，带宽压缩 97%
3. **异步本地迭代**：节点可本地迭代 15-250 步后再同步（不像传统集群逐步同步）
4. **对象存储中继**：参与者创建对象存储 bucket，将 read key 和 bucket 位置发布到链上

### 行业认可
- **2026-03-20**：NVIDIA CEO 黄仁勋评价 Covenant-72B 为"现代版 Folding@home"
- Chamath Palihapitiya 向黄仁勋展示了这一成果，描述为"用分布式算力训练 Llama 模型，全程分布式且保持状态"
- SN3 alpha token 一个月内上涨 **444%**，市值达 **$1.37 亿**
- TAO 代币同步翻倍，峰值 $377

---


## 8. 挑战与风险

### 技术挑战

- **评估难题**：某些 AI 任务难以自动化评估质量（如创意生成）
- **延迟**：去中心化推理相比中心化 API 有更高延迟
- **模型安全**：Miner 运行的模型可能存在安全隐患
- **SparseLoCo 的局限**：97% 压缩率在更大模型上是否仍然有效？

### 经济风险

- **Emission 集中**：头部 Miner/Validator 可能形成垄断
- **Subnet 存活率**：大量子网可能无法持续吸引参与者
- **dTAO 投机**：SN3 一个月涨 444% 说明市场可能过度投机

### 生态风险

- **与中心化 AI 竞争**：OpenAI/Anthropic/Google 的模型持续进步
- **监管不确定性**：代币化 AI 市场的监管前景不明
- **开发者采用**：相比直接使用 API，子网开发的学习曲线较陡

## 参考链接

**文档 & 代码**

| 资源 | 地址 |
|------|------|
| 官方文档 | [docs.bittensor.com](https://docs.bittensor.com) |
| Bittensor Python SDK | [github.com/opentensor/bittensor](https://github.com/opentensor/bittensor) |
| Subtensor 区块链 | [github.com/opentensor/subtensor](https://github.com/opentensor/subtensor) |
| Subnet 模板 | [github.com/latent-to/bittensor-subnet-template](https://github.com/latent-to/bittensor-subnet-template) |
| SN3 Templar 源码 | [github.com/tplr-ai/templar](https://github.com/tplr-ai/templar) |
| Covenant-72B 报告 | [templarresearch.substack.com](https://templarresearch.substack.com/p/checkpoint-one) |

**网络监控**

| 资源 | 地址 |
|------|------|
| 全网浏览器 | [taostats.io](https://taostats.io) |
| SN3 Metagraph | [taostats.io/subnets/3/metagraph](https://taostats.io/subnets/3/metagraph) |
| SN19 Metagraph | [taostats.io/subnets/19/metagraph](https://taostats.io/subnets/19/metagraph) |
| SN64 Metagraph | [taostats.io/subnets/64/metagraph](https://taostats.io/subnets/64/metagraph) |

**推理 API 入口**

| 资源 | 地址 |
|------|------|
| SN19 Nineteen | [nineteen.ai/app/api](https://nineteen.ai/app/api) |
| SN64 Chutes | [chutes.ai/docs/getting-started/quickstart](https://chutes.ai/docs/getting-started/quickstart) |