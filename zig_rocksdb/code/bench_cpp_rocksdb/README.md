
## Run commands: 
```bash
sudo apt update
sudo apt install -y build-essential cmake libgflags-dev libsnappy-dev zlib1g-dev libbz2-dev liblz4-dev libzstd-dev
# 安装 rocksdb，如果系统仓库有 librocksdb-dev
sudo apt install -y librocksdb-dev
# 如果没有 librocksdb-dev，你可以从源码编译安装 RocksDB（略，必要时我可以给出步骤）

mkdir build && cd build
cmake ..
make -j$(nproc)

cd ..
g++ -std=c++20 main.cpp -o bench_cpp_rocksdb \
  -I/usr/local/include -L/usr/local/lib \
  -lrocksdb -lpthread -lz -lsnappy -lzstd -llz4 -lbz2

# 创建数据目录
mkdir -p ./data/testdb

# 初始化填充（-n 表示需要初始化写入）
./bench_rocksdb_cpp -n -t 8 -w 1000000 -r 1000000 -p ./data/testdb -l 3
```

