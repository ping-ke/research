cd ../bench_cpp_rocksdb
g++ -std=c++20 main.cpp -o bench_cpp_rocksdb   -I/usr/local/include -L/usr/local/lib   -lrocksdb -lpthread -lz -lsnappy -lzstd -llz4 -lbz2
cd ../bench_go_leveldb
go build
cd ../bench_go_ethleveldb
go build
cd ../bench_zig_rocksdb
zig build
cd ../bench_zig_rocksdb_capi
zig build
