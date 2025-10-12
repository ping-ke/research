# Zig RocksDB Benchmark

A performance benchmark project for [RocksDB](https://github.com/facebook/rocksdb) written in **Zig**,  
using the [jiacai2050/zig-rocksdb](https://github.com/jiacai2050/zig-rocksdb) wrapper.

This example demonstrates how to use RocksDB from Zig and measure basic read/write performance.

---

## 🚀 Environment Setup

### 1. Install Zig

This project requires **Zig 0.13.0 or newer**.

#### On Ubuntu:

```bash
sudo apt update
sudo apt install curl -y
curl -O https://ziglang.org/download/0.13.0/zig-linux-x86_64-0.13.0.tar.xz
tar -xf zig-linux-x86_64-0.13.0.tar.xz
sudo mv zig-linux-x86_64-0.13.0 /usr/local/zig
sudo ln -s /usr/local/zig/zig /usr/local/bin/zig

# Verify installation:
zig version
```

### 2. Install Dependencies

This project depends on [jiacai2050/zig-rocksdb](https://github.com/jiacai2050/zig-rocksdb).

Run the following command to fetch and save the dependency
(it will be recorded in build.zig.zon):
```bash
zig fetch --save=rocksdb https://github.com/jiacai2050/zig-rocksdb/archive/refs/heads/main.tar.gz
```


### 3. Run the Benchmark

Run:

```bash
zig build run
```
Example output:
```
Wrote 100000 records in 1234 ms
Read 100000/100000 records in 832 ms
```


### 4. Common Issues
**1. `undefined reference to rocksdb...`**

This means RocksDB was not linked correctly.
Solutions:
- Keep .link_vendor = true (default), or
- Install RocksDB system-wide:
    ```bash
    sudo apt install librocksdb-dev
    ```
**2. `zig fetch --save` not found**

Your Zig version is too old.
Upgrade to **Zig 0.13.0 or newer**.


### Performance Notes

This benchmark uses 32-byte random keys and 110-byte average values.

You can modify parameters in bench_rocksdb.zig for different workloads.

To enable multi-threaded tests, run:

```bash
zig build run --threads 4
```