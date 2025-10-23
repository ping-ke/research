writeCount=10000000
readCount=10000000
sleepTime=300
loglevel=2
threads=$1


echo "---------------------------------------------------- threads $threads -------------------------------------------------------------------------"

sleep $sleepTime
echo "====================================== bench_go_leveldb ============================================"
cd ../bench_go_leveldb/
./bench_go_leveldb --loglevel 2 --threads $threads --write $writeCount --read $readCount


sleep $sleepTime
echo "====================================== bench_zig_rocksdb ============================================"
cd ../bench_zig_rocksdb
./zig-out/bin/bench_zig_rocksdb -v 2 -t $threads -w $writeCount -r $readCount


sleep $sleepTime
echo "====================================== bench_zig_rocksdb_capi ============================================"
cd ../bench_zig_rocksdb_capi
./zig-out/bin/bench_zig_rocksdb_capi -v 2 -t $threads -w $writeCount -r $readCount


sleep $sleepTime
echo "====================================== bench_cpp_rocksdb ============================================"
cd ../bench_cpp_rocksdb
./bench_cpp_rocksdb -l 2 -t $threads -w $writeCount -r $readCount