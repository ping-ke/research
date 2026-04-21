import bittensor as bt

# 1️⃣ 连接主网（先别用 testnet，稳定性差）
subtensor = bt.Subtensor(network="finney")

# 2️⃣ 钱包（必须存在本地）
wallet = bt.Wallet(name="mywallet", hotkey="myhotkey")

# 3️⃣ 客户端
dendrite = bt.Dendrite(wallet=wallet)

# 4️⃣ 选择一个 subnet（常用从 1 开始试）
netuid = 1
metagraph = subtensor.metagraph(netuid=netuid)

# 5️⃣ 只选在线的 axon（提高成功率）
axons = [a for a in metagraph.axons if a.is_serving][:5]

print(f"Using {len(axons)} axons")

# 6️⃣ 定义一个最简单的 synapse
class Ping(bt.Synapse):
    message: str

# 7️⃣ 发请求
responses = dendrite.query(
    axons=axons,
    synapse=Ping(message="hello"),
    timeout=12,
)

# 8️⃣ 打印返回
for i, r in enumerate(responses):
    print(f"Response {i}: {r}")