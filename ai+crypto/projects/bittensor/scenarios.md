# Bittensor + EVM + AI API 商业化架构图

## 一、整体架构（调用链 + 资金流）

以下图为基于当前功能想象的使用场景，需要修改
```text
                         ┌───────────────────────────┐
                         │        前端 / 客户端       │
                         │  Web / App / SDK / CLI    │
                         └────────────┬──────────────┘
                                      │
                         HTTP / SDK   │
                                      ▼
                         ┌───────────────────────────┐
                         │        API Gateway         │
                         │  - 鉴权（API Key / JWT）   │
                         │  - 限流 / 配额             │
                         │  - 路由不同模型            │
                         └────────────┬──────────────┘
                                      │
                         （调用前校验付费状态）
                                      │
                                      ▼
                 ┌──────────────────────────────────────┐
                 │      收费层（EVM 智能合约）           │
                 │  - 预充值余额（prepaid）             │
                 │  - 按调用扣费（pay-per-call）        │
                 │  - 订阅（subscription NFT / token）  │
                 │  - 计费单位：token / request / time  │
                 └────────────┬────────────────────────┘
                              │
                （余额校验 / 扣费成功才放行）
                              │
                              ▼
                 ┌──────────────────────────────────────┐
                 │          Validator 服务层            │
                 │  - dendrite（请求客户端）            │
                 │  - 路由 miners                       │
                 │  - 结果聚合 / 过滤                   │
                 │  - 质量评分（scoring）               │
                 └────────────┬────────────────────────┘
                              │  (P2P RPC / off-chain)
                              ▼
     ┌────────────────────────────────────────────────────┐
     │                   Miners（算力层）                 │
     │  ┌──────────────┐   ┌──────────────┐               │
     │  │   Miner A    │   │   Miner B    │   ...         │
     │  │ axon server  │   │ axon server  │               │
     │  │ LLM / RAG    │   │ Diffusion    │               │
     │  └──────────────┘   └──────────────┘               │
     └────────────────────────────────────────────────────┘
                              │
                              ▼
                 ┌──────────────────────────────────────┐
                 │          Validator                   │
                 │  - 排序 / 选优                       │
                 │  - 返回结果给 API 层                 │
                 └────────────┬────────────────────────┘
                              │
                              ▼
                         ┌───────────────┐
                         │ 返回给用户     │
                         └───────────────┘

                ─────────────── 链上路径 ────────────────
                              │
                              ▼
                 ┌──────────────────────────────────────┐
                 │   Bittensor 主链（Subtensor）         │
                 │  - set_weights（评分上链）            │
                 │  - staking / emission                │
                 └──────────────────────────────────────┘
```

## 二、收费模型设计（3种主流）
1️⃣ 预付费（Prepaid Credits）
用户 → 向 EVM 合约充值 → 获得余额
每次调用 → API 查询余额 → 扣费 → 执行

特点：

类似 OpenAI credits
易实现、用户体验好
2️⃣ 按调用付费（Pay-per-call）
每次请求：
用户签名 → 合约验证 → 扣费 → 放行请求

特点：

精细计费（token / 请求）
适合高价值 API
3️⃣ 订阅制（Subscription）
用户持有 NFT / token
→ API 验证持仓
→ 免费或限额调用

特点：

Web3-native
适合 SaaS 模式


## 三、资金流（核心）
用户
  ↓（支付）
EVM 合约（收费层）
  ↓
项目方 / Validator 收益
  ↓
用于：
  - 补贴 miner（链下支付 or 自运营）
  - 增加 stake（提升收益）


## 四、关键模块说明
🔹 API Gateway
API Key / JWT
Rate limit
Usage tracking
🔹 EVM 合约层
账户余额（mapping）
扣费逻辑
订阅 / NFT gating
支付 token（TAO / ERC20）
🔹 Validator（核心调度）
选 miner
并发请求
scoring
fallback / retry
🔹 Miner（算力提供）
LLM / embedding / diffusion
自由实现（Python）
被动接单

## 五、与传统 Web2 AI 架构对比

| 模块  | Web2（OpenAI） | Bittensor 方案   |
| --- | ------------ | -------------- |
| API | OpenAI API   | 自建 API Gateway |
| 模型  | 自有           | 去中心化 miners    |
| 调度  | 内部           | validator      |
| 收费  | Stripe       | EVM 合约         |
| 激励  | 公司利润         | emission + fee |

