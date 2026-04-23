# Bittensor 技术分享 PPT 设计文档

**日期：** 2026-04-22  
**工具：** Marp + VS Code 插件（gaia 主题）  
**输出：** `projects/bittensor/slides-bittensor.md` → 导出 PPTX  
**内容来源：** `bittensor.md` + `scenarios.md` + `consensus.md`

---

## 结构设计

叙事策略：**故事线驱动（方案 B）**  
用 Covenant-72B 真实案例开场（Why it matters）→ 讲清架构机制（How it works）→ 落地用法（How to use）→ 原理回溯（Why it worked）→ 风险收尾

总幻灯片数：**约 34 张**

---

## 幻灯片清单

### Part 0：开场钩子（3 张）
| # | 标题 | 内容来源 | 关键内容 |
|---|------|----------|----------|
| 1 | 标题页 | — | "Bittensor 技术分享 / 去中心化 AI 能力市场" |
| 2 | 2026.3.20，黄仁勋说了什么？ | bittensor.md §7 | 黄仁勋引言 + SN3 alpha 涨 444%，TAO 峰值 $377 |
| 3 | Covenant-72B 成就 | bittensor.md §7 | 72B 参数 / 1.1T token / 70+ 节点 / MMLU 67.1 / 普通商用网络 |

### Part 1：Bittensor 是什么（3 张）
| # | 标题 | 内容来源 | 关键内容 |
|---|------|----------|----------|
| 4 | 核心定位 | bittensor.md §1 | 比特币激励矿工 → Bittensor 激励 GPU 节点竞争最优 AI |
| 5 | vs 以太坊 | bittensor.md §1 | 对比表（解决问题/节点工作/共识目标/链技术） |
| 6 | 本质定义 | bittensor.md §1 | "链上 AI 质量排名系统" |

### Part 2：网络架构（3 张）
| # | 标题 | 内容来源 | 关键内容 |
|---|------|----------|----------|
| 7 | 三层结构 | bittensor.md §2 | ASCII 三层图（Subtensor / Subnets / Miner+Validator） |
| 8 | 角色与收益 | bittensor.md §2 | 表格：Miner 41% / Validator 41% / Owner 18% |
| 9 | SDK 命名来源 | bittensor.md §2 | 神经科学隐喻表（Axon/Dendrite/Synapse/Metagraph） |

### Part 3：核心流程（3 张）
| # | 标题 | 内容来源 | 关键内容 |
|---|------|----------|----------|
| 10 | Miner-Validator 交互 | bittensor.md §3 | mermaid sequenceDiagram |
| 11 | Emission 两阶段 | bittensor.md §3 | Injection（每 block）+ Distribution（每 tempo） |
| 12 | Subnet 生命周期 | bittensor.md §3 | mermaid flowchart LR |

### Part 4：Yuma Consensus（7 张）
| # | 标题 | 内容来源 | 关键内容 |
|---|------|----------|----------|
| 13 | 为什么需要 Yuma Consensus？ | consensus.md §1 | 防勾结问题 + 三个防护机制表格 |
| 14 | 算法六步总览 | consensus.md §2 | 伪代码：质押加权→中位数→Clipping→Rank→Incentive→Bond→Dividends |
| 15 | 示例场景设定 | consensus.md §3 | V1=100 TAO / V2=60 TAO / M0 M1 M2 权重表 |
| 16 | 加权中位数计算 | consensus.md §3 | M0 C=0.7，M1 C=0.2，规律说明 |
| 17 | Clipping 过程 | consensus.md §3 | V2 对 M1: 0.5→0.2（高于共识截断），M0: 0.4 保留 |
| 18 | Rank / Incentive / Trust | consensus.md §3 | M0=94/0.662，M1=32/0.225，Trust M1=0.64 |
| 19 | Emission 分配结论 | consensus.md §3 | V2 偷分 → Dividends 12.1 < V1 的 28.9，偷分无效 |

### Part 5：经济学 dTAO（3 张）
| # | 标题 | 内容来源 | 关键内容 |
|---|------|----------|----------|
| 20 | TAO 参数 + AMM 池 | bittensor.md §5 | 参数表 + AMM 质押/取消质押代码块 |
| 21 | 质押 TAO = 为子网投票 | bittensor.md §5 | EMA 净流入机制 + 市场正负反馈 |
| 22 | Alpha 价格为什么低 | bittensor.md §5 | 持续卖压 + 典型数据 SN1 |

### Part 6：商业化场景（3 张）
| # | 标题 | 内容来源 | 关键内容 |
|---|------|----------|----------|
| 23 | 整体调用链架构 | scenarios.md §1 | mermaid flowchart TD（User→GW→Pay→V→Miners→Chain） |
| 24 | 三种收费模型 | scenarios.md §2 | 表格：预付费 Credits / 按调用 / 订阅制 |
| 25 | Web2 vs Bittensor | scenarios.md §5 | 对比表（API/模型/调度/收费/激励/抗审查） |

### Part 7：Demo（2 张）
| # | 标题 | 内容来源 | 关键内容 |
|---|------|----------|----------|
| 26 | Demo A：调用现有子网 | scenarios.md §3 | SN64 Chutes + SN19 Nineteen 代码 |
| 27 | Demo B：自建 Validator | scenarios.md §4 | mermaid + btcli + curl 命令 |

### Part 8：SDK 接口（3 张）
| # | 标题 | 内容来源 | 关键内容 |
|---|------|----------|----------|
| 28 | 三个核心文件 | bittensor.md §6 | 目录树 + pip install |
| 29 | 定义协议 + Miner | bittensor.md §6 | protocol.py + miner.py 代码 |
| 30 | Validator 实现 | bittensor.md §6 | validator.py 代码 + set_weights |

### Part 9：技术深挖 SparseLoCo（2 张）
| # | 标题 | 内容来源 | 关键内容 |
|---|------|----------|----------|
| 31 | 去中心化训练的带宽瓶颈 | bittensor.md §7 | 传统 DDP vs 商用互联网带宽问题 |
| 32 | SparseLoCo 解决方案 | bittensor.md §7 | 本地迭代→1-3% 梯度→2-bit 量化→对象存储异步 |

### Part 10：挑战与风险（1 张）
| # | 标题 | 内容来源 | 关键内容 |
|---|------|----------|----------|
| 33 | 挑战与风险 | bittensor.md §8 | 技术 / 经济 / 生态三类 bullet |

### Part 11：参考链接（1 张）
| # | 标题 | 内容来源 | 关键内容 |
|---|------|----------|----------|
| 34 | 参考链接 | bittensor.md §参考 | 文档/代码/监控/API 入口分类表 |

---

## 技术规格

### Marp 配置
```yaml
---
marp: true
theme: gaia
paginate: true
style: |
  section {
    font-family: "PingFang SC", "Microsoft YaHei", sans-serif;
    font-size: 22px;
  }
  section.lead h1 { font-size: 52px; }
  code { font-size: 16px; }
  table { font-size: 17px; }
---
```

### 特殊处理
- **mermaid 图**：Marp gaia 主题支持 mermaid，直接使用 ` ```mermaid ``` ` 代码块
- **图片**：`bittensor-subnets.png`、`how-bittensor-actually-work.png`、`bittensor-feedback-loop.png` 已在 `images/` 目录，按需插入
- **长代码块**：超过 15 行的代码拆分到两张 slide，或用 `font-size: 13px` 压缩
- **章节分隔页**：每个 Part 用 `<!-- _class: lead -->` 生成深色大字分隔页

### 导出方式
1. VS Code 安装 `Marp for VS Code` 插件
2. 打开 `slides-bittensor.md`
3. 右上角点击 Marp 图标 → Export Slide Deck → PPTX

---

## 输出文件

- `projects/bittensor/slides-bittensor.md`（主文件，覆盖旧版）
