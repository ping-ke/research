import time
import bittensor as bt
import utils

class Miner:

    def __init__(self):
        self.config = utils.get_config()
        self.wallet = bt.Wallet(config=self.config)
        self.subtensor = bt.Subtensor(config=self.config)

        # axon = 对外服务接口
        self.axon = bt.Axon(
            wallet=self.wallet,
            config=self.config
        )

        # 注册 forward
        self.axon.attach(
            forward_fn=self.forward
        )

    def forward(self, synapse: utils.TextSynapse) -> utils.TextSynapse:
        start = time.time()

        # fake LLM
        synapse.response = f"Echo: {synapse.prompt}"
        print(f"[Miner] Received request: {synapse.prompt}")

        synapse.latency = time.time() - start
        return synapse

    def run(self):
        # serve() 把端点注册到链上；本地 demo 可跳过，直接 start() 监听
        try:
            self.axon.serve(netuid=self.config.netuid, subtensor=self.subtensor)
        except Exception as e:
            print(f"[warn] axon.serve skipped (not registered on-chain): {e}")

        self.axon.start()
        print(f"Miner running on port {self.axon.port}")

        while True:
            time.sleep(10)


if __name__ == "__main__":
    miner = Miner()
    miner.run()