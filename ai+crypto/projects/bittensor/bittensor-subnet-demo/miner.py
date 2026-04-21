import time
import bittensor as bt
from protocol import TextSynapse

class Miner:

    def __init__(self):
        self.config = bt.config()
        self.wallet = bt.wallet(config=self.config)
        self.subtensor = bt.subtensor(config=self.config)

        # axon = 对外服务接口
        self.axon = bt.axon(
            wallet=self.wallet,
            config=self.config
        )

        # 注册 forward
        self.axon.attach(
            forward_fn=self.forward
        )

    def forward(self, synapse: TextSynapse) -> TextSynapse:
        start = time.time()

        # fake LLM
        synapse.response = f"Echo: {synapse.prompt}"

        synapse.latency = time.time() - start
        return synapse

    def run(self):
        self.axon.serve(netuid=self.config.netuid, subtensor=self.subtensor)
        self.axon.start()

        print("Miner running...")

        while True:
            time.sleep(10)


if __name__ == "__main__":
    miner = Miner()
    miner.run()