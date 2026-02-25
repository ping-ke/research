## Run commands: 
```bash
sudo apt update
sudo apt install -y build-essential cmake libgflags-dev libsnappy-dev zlib1g-dev libbz2-dev liblz4-dev libzstd-dev
sudo apt install -y librocksdb-dev

mkdir build && cd build
cmake ..
make -j$(nproc)

cd ..
g++ -std=c++20 main.cpp -o bench_cpp_rocksdb \
  -I/usr/local/include -L/usr/local/lib \
  -lrocksdb -lpthread -lz -lsnappy -lzstd -llz4 -lbz2

# create data folder
mkdir -p ./data

# Sample run
./bench_rocksdb -n -T 2000000000 -t 16 -w 0 -r 1000000 

# Usage：
# -n：init insert data 
# -b: batch insert
# -c: force compact after init insert data
# -T：total number of keys count
# -t: threads
# -w：random write count 
# -r：random read count
# -p：db path
# -l：log level
```

