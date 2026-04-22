import asyncio
import traceback
import bittensor as bt
import uvicorn
from contextlib import asynccontextmanager
from fastapi import FastAPI
from pydantic import BaseModel
import utils

# 本地 demo：直连这些 Miner（不走链上 Metagraph）
LOCAL_MINERS = [
    ("127.0.0.1", 8091),
]


class ChatRequest(BaseModel):
    prompt: str


class Validator:

    def __init__(self):
        self.config = utils.get_config()
        self.wallet = bt.Wallet(config=self.config)
        self.dendrite = None  # 在 uvicorn event loop 启动后初始化

        self.local_axons = [
            bt.AxonInfo(
                version=1,
                ip=ip,
                port=port,
                ip_type=4,
                hotkey=self.wallet.hotkey.ss58_address,
                coldkey=self.wallet.coldkey.ss58_address,
            )
            for ip, port in LOCAL_MINERS
        ]

    async def query_miners(self, prompt, axons=None):
        if axons is None:
            axons = self.local_axons

        synapse = utils.TextSynapse(prompt=prompt)

        responses = await self.dendrite.forward(
            axons=axons,
            synapse=synapse,
            timeout=5
        )

        print("Received responses:")
        for i, resp in enumerate(responses):
            if resp is None:
                print(f"  Miner {i}: No response")
            else:
                print(f"  Miner {i}: response='{resp.response}' latency={resp.latency:.2f}s")
        return responses

    def best_response(self, responses):
        valid = [r for r in responses if r and r.response]
        if not valid:
            return ""
        return max(valid, key=lambda r: len(r.response) - r.latency * 10).response

    def score(self, responses):
        scores = []
        for resp in responses:
            if resp is None:
                scores.append(0)
                continue
            score = len(resp.response) - resp.latency * 10
            scores.append(max(score, 0))

        total = sum(scores) + 1e-6
        return [s / total for s in scores]

    def set_weights(self, uids, weights):
        try:
            subtensor = bt.Subtensor(config=self.config)
            subtensor.set_weights(
                netuid=self.config.netuid,
                wallet=self.wallet,
                uids=uids,
                weights=weights,
            )
            print("set_weights ok")
        except Exception as e:
            print(f"[warn] set_weights skipped (not registered on-chain): {e}")

    async def _scoring_loop(self):
        while True:
            responses = await self.query_miners("What is Bittensor?")
            weights = self.score(responses)
            uids = list(range(len(weights)))
            print("Scores:", [f"{w:.3f}" for w in weights])
            self.set_weights(uids, weights)
            await asyncio.sleep(30)

    def run(self):
        validator = self

        @asynccontextmanager
        async def lifespan(app: FastAPI):
            # 在 uvicorn event loop 内创建 Dendrite，避免 loop 绑定问题
            validator.dendrite = bt.Dendrite(wallet=validator.wallet)
            asyncio.create_task(validator._scoring_loop())
            yield

        app = FastAPI(lifespan=lifespan)

        @app.post("/chat")
        async def chat(req: ChatRequest):
            try:
                responses = await validator.query_miners(req.prompt)
                return {"response": validator.best_response(responses)}
            except Exception as e:
                traceback.print_exc()
                return {"error": str(e)}

        print("Validator HTTP API running on http://0.0.0.0:8000")
        print("POST /chat  body: {\"prompt\": \"...\"}")
        print(f"Connecting to local miners: {LOCAL_MINERS}")
        uvicorn.run(app, host="0.0.0.0", port=8000)


if __name__ == "__main__":
    validator = Validator()
    validator.run()
