import argparse
import bittensor as bt

def get_config():
    parser = argparse.ArgumentParser()
    parser.add_argument("--netuid", type=int, default=1)
    parser.add_argument("--wallet.name", type=str, default="mywallet")
    parser.add_argument("--wallet.hotkey", type=str, default="myhotkey")
    return bt.Config(parser)

class TextSynapse(bt.Synapse):
    prompt: str
    response: str = ""
    latency: float = 0.0