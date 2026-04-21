import bittensor as bt

def get_config():
    parser = bt.config()
    parser.add_argument("--netuid", type=int, default=1)
    parser.add_argument("--wallet.name", type=str, default="default")
    parser.add_argument("--wallet.hotkey", type=str, default="default")
    return bt.config(parser)