#include <rocksdb/db.h>
#include <rocksdb/options.h>
#include <iostream>
#include <chrono>
#include <thread>
#include <random>
#include <vector>

std::string random_bytes(size_t len) {
    static thread_local std::mt19937_64 rng{std::random_device{}()};
    static std::uniform_int_distribution<unsigned char> dist(0, 255);
    std::string s(len, '\0');
    for (size_t i = 0; i < len; ++i) s[i] = dist(rng);
    return s;
}

void writer(rocksdb::DB* db, size_t start, size_t end) {
    for (size_t i = start; i < end; ++i) {
        std::string key = random_bytes(32);
        std::string value = random_bytes(110);
        db->Put(rocksdb::WriteOptions(), key, value);
    }
}

void reader(rocksdb::DB* db, size_t reads) {
    for (size_t i = 0; i < reads; ++i) {
        std::string key = random_bytes(32);
        std::string value;
        db->Get(rocksdb::ReadOptions(), key, &value);
    }
}

int main(int argc, char* argv[]) {
    const std::string db_path = "rocksdb_mt_bench";
    const size_t total_keys = 100000;
    const size_t sample_reads = 10000;
    const int threads = (argc > 1) ? std::stoi(argv[1]) : 8;

    rocksdb::Options options;
    options.create_if_missing = true;
    options.compression = rocksdb::kNoCompression;

    rocksdb::DB* db;
    rocksdb::Status status = rocksdb::DB::Open(options, db_path, &db);
    if (!status.ok()) return 1;

    std::cout << "Threads: " << threads << "\n";

    // --- 写入阶段 ---
    auto start = std::chrono::steady_clock::now();
    std::vector<std::thread> ws;
    size_t per = total_keys / threads;
    for (int i = 0; i < threads; ++i)
        ws.emplace_back(writer, db, i * per, (i + 1) * per);
    for (auto& t : ws) t.join();
    auto end = std::chrono::steady_clock::now();

    double w_ms = std::chrono::duration<double, std::milli>(end - start).count();
    std::cout << "Write: " << total_keys << " ops in " << w_ms
              << " ms (" << total_keys * 1000 / w_ms << " ops/s)\n";

    // --- 读取阶段 ---
    auto rstart = std::chrono::steady_clock::now();
    std::vector<std::thread> rs;
    size_t rper = sample_reads / threads;
    for (int i = 0; i < threads; ++i)
        rs.emplace_back(reader, db, rper);
    for (auto& t : rs) t.join();
    auto rend = std::chrono::steady_clock::now();

    double r_ms = std::chrono::duration<double, std::milli>(rend - rstart).count();
    std::cout << "Read: " << sample_reads << " ops in " << r_ms
              << " ms (" << sample_reads * 1000 / r_ms << " ops/s)\n";

    delete db;
}
