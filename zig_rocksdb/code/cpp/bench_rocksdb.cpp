#include <rocksdb/db.h>
#include <rocksdb/options.h>
#include <iostream>
#include <chrono>
#include <random>
#include <vector>

std::string random_bytes(size_t len) {
    static thread_local std::mt19937_64 rng{std::random_device{}()};
    static std::uniform_int_distribution<unsigned char> dist(0, 255);
    std::string s;
    s.resize(len);
    for (size_t i = 0; i < len; ++i) s[i] = dist(rng);
    return s;
}

int main() {
    const std::string db_path = "rocksdb_bench";
    const size_t total_keys = 100000;
    const size_t sample_reads = 10000;

    rocksdb::Options options;
    options.create_if_missing = true;
    options.compression = rocksdb::kNoCompression;

    rocksdb::DB* db;
    rocksdb::Status status = rocksdb::DB::Open(options, db_path, &db);
    if (!status.ok()) {
        std::cerr << "Open DB failed: " << status.ToString() << std::endl;
        return 1;
    }

    // ---- 写入测试 ----
    auto start_write = std::chrono::steady_clock::now();
    for (size_t i = 0; i < total_keys; ++i) {
        std::string key = random_bytes(32);
        std::string value = random_bytes(110);
        db->Put(rocksdb::WriteOptions(), key, value);
    }
    auto end_write = std::chrono::steady_clock::now();
    double write_ms = std::chrono::duration<double, std::milli>(end_write - start_write).count();
    std::cout << "Write: " << total_keys << " ops in " << write_ms
              << " ms (" << total_keys * 1000 / write_ms << " ops/s)\n";

    // ---- 随机读取 ----
    std::vector<std::string> keys;
    db->NewIterator(rocksdb::ReadOptions());
    for (size_t i = 0; i < sample_reads; ++i) {
        keys.push_back(random_bytes(32));
    }

    auto start_read = std::chrono::steady_clock::now();
    for (auto &k : keys) {
        std::string v;
        db->Get(rocksdb::ReadOptions(), k, &v);
    }
    auto end_read = std::chrono::steady_clock::now();
    double read_ms = std::chrono::duration<double, std::milli>(end_read - start_read).count();
    std::cout << "Read: " << sample_reads << " ops in " << read_ms
              << " ms (" << sample_reads * 1000 / read_ms << " ops/s)\n";

    delete db;
}
