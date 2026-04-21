import bittensor as bt

class TextSynapse(bt.Synapse):
    prompt: str
    response: str = ""
    latency: float = 0.0