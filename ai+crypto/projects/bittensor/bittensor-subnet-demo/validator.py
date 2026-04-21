import time
import bittensor as bt
from protocol import TextSynapse

class Validator:

    def __init__(self):
        self.config = bt.config()
        self.wallet = bt.wallet(config=self.config)
        self.subtensor = bt.subtensor(config=self.config)

        # dendrite = 客户端
        self.dendrite = bt.dendrite(wallet=self.wallet)

        self.metagraph = self.subtensor.metagraph(self.config.netuid)

    def query_miners(self, prompt):

        synapse = TextSynapse(prompt=prompt)

        # 查询所有 miner
        responses = self.dendrite.query(
            axons=self.metagraph.axons,
            synapse=synapse,
            timeout=5
        )

        return responses

    def score(self, responses):

        scores = []

        for resp in responses:

            if resp is None:
                scores.append(0)
                continue

            # 简单评分逻辑
            score = len(resp.response) - resp.latency * 10
            scores.append(max(score, 0))

        # normalize
        total = sum(scores) + 1e-6
        weights = [s / total for s in scores]

        return weights

    def set_weights(self, weights):

        self.subtensor.set_weights(
            netuid=self.config.netuid,
            wallet=self.wallet,
            uids=self.metagraph.uids,
            weights=weights
        )

    def run(self):

        while True:

            responses = self.query_miners("What is Bittensor?")

            weights = self.score(responses)

            self.set_weights(weights)

            print("Weights:", weights)

            time.sleep(30)


if __name__ == "__main__":
    validator = Validator()
    validator.run()