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
mkdir -p ./data

# 初始化填充（-n 表示需要初始化写入）
./bench_cpp_rocksdb -n -T 40000000 -t 16 -w 1000000 -r 1000000 
# 参数说明：
# -n：是否需要初始化大量 key（boolean flag，存在即为 true）
# -T：total 
# -t: threads
# -w：写操作总数
# -r：读操作总数
# -p：db path
# -l：log level
```

