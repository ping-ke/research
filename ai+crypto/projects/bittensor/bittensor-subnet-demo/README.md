# Bittensor Subnet Demo

## 1. 安装

pip install -r requirements.txt

## 2. 启动本地 subtensor（或连接 testnet）

btcli subnets list

## 3. 注册

btcli subnets register --netuid 1

## 4. 启动 miner

python miner.py --netuid 1

## 5. 启动 validator

python validator.py --netuid 1