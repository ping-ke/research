
技术栈与工具链

### 安装

```bash
# Python SDK（核心库）
pip install bittensor

# CLI 工具（btcli 命令行）—— 注意包名不是 btcli
pip install bittensor-cli

# 验证安装
btcli --version
```

> **注意**：PyPI 上不存在 `btcli` 包，正确包名是 `bittensor-cli`。`bittensor` 包是 Python SDK。

### btcli 常用命令

| 命令 | 用途 |
|------|------|
| `btcli wallet create` | 创建 coldkey/hotkey 钱包对 |
| `btcli wallet overview` | 查看余额、质押、注册状态 |
| `btcli subnet list` | 列出所有活跃子网 |
| `btcli subnet metagraph --netuid 3` | 查看 SN3 的所有 Miner/Validator 状态 |
| `btcli subnet create` | 创建新子网 |
| `btcli subnet register` | 在子网注册 hotkey |
| `btcli stake add` | 质押 TAO |

### Sample
```bash
# 创建 coldkey（主账户）
btcli wallet new_coldkey --wallet.name mywallet
# 创建 hotkey（用于操作）
btcli wallet new_hotkey --wallet.name mywallet --wallet.hotkey myhotkey
# 查看钱包地址
btcli wallet list
btcli wallet overview

# 查看 testnet 余额
btcli wallet balance --wallet.name mywallet --subtensor.network test

# 查看 Subnet
btcli subnet list --subtensor.network test
# 查看 Validator / Neuron
btcli subnet metagraph --netuid 1 --subtensor.network test
btcli subnet metagraph --netuid 1 --subtensor.network test --json-output --no-prompt

# 给某个 hotkey stake
# --hotkey-ss58-address：目标 validator（默认是你自己的）
btcli stake add   --wallet.name mywallet   --wallet-hotkey myhotkey   --hotkey-ss58-address 5GrwvaEF5zXb26Fz9rcQpDWS57CtERHpNehXCPcNoHGKutQY   --amount 1   --netuid 1   --subtensor.network test

# 查看 stake 
btcli stake list --wallet.name mywallet --subtensor.network test

# 创建 subnet
btcli subnet create --wallet.name mywallet --wallet.hotkey myhotkey --subtensor.network test
# 加入 subnet
btcli subnet register --netuid 461 --wallet.name mywallet --wallet.hotkey myhotkey  --subtensor.network test

# 启动 miner
python miner.py --netuid 461

## 启动 validator
python validator.py --netuid 461

## 访问 validator 
curl -X POST http://localhost:8000/chat -H "Content-Type: application/json" -d '{"prompt": "今天天气如何"}'
```



### 核心仓库

| 仓库 | 说明 |
|------|------|
| [opentensor/bittensor](https://github.com/opentensor/bittensor) | Python SDK |
| [opentensor/btcli](https://github.com/opentensor/btcli) | CLI 工具 |
| [opentensor/subtensor](https://github.com/opentensor/subtensor) | 区块链节点 (Rust/Substrate) |
| [opentensor/bittensor-subnet-template](https://github.com/opentensor/bittensor-subnet-template) | Subnet 开发模板 |
| [tplr-ai/templar](https://github.com/tplr-ai/templar) | **SN3 Templar 源码** |
