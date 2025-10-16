const std = @import("std");
const rocksdb = @import("rocksdb");

fn random_bytes(allocator: std.mem.Allocator, len: usize) []u8 {
    var buf = allocator.alloc(u8, len) catch unreachable;
    var prng = std.rand.DefaultPrng.init(@intCast(u64, std.time.timestamp()));
    var r = prng.random();
    for (buf) |*b| b.* = r.int(u8);
    return buf;
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const db_path = "zig-rocksdb-bench";
    const total_keys = 100_000;
    const sample_reads = 10_000;

    var opts = rocksdb.Options{};
    opts.create_if_missing = true;
    var db = try rocksdb.DB.open(opts, db_path);

    var timer = try std.time.Timer.start();
    var i: usize = 0;
    while (i < total_keys) : (i += 1) {
        const key = random_bytes(allocator, 32);
        const value = random_bytes(allocator, 110);
        _ = db.put(key, value) catch {};
        allocator.free(key);
        allocator.free(value);
    }

    const write_ms = @as(f64, @floatFromInt(timer.read())) / 1_000_000.0;
    std.debug.print("Write: {d} ops in {d:.2} ms ({d:.2} ops/s)\n", .{ total_keys, write_ms, total_keys * 1000 / write_ms });

    timer.reset();

    i = 0;
    while (i < sample_reads) : (i += 1) {
        const key = random_bytes(allocator, 32);
        _ = db.get(key) catch {};
        allocator.free(key);
    }

    const read_ms = @as(f64, @floatFromInt(timer.read())) / 1_000_000.0;
    std.debug.print("Read: {d} ops in {d:.2} ms ({d:.2} ops/s)\n", .{ sample_reads, read_ms, sample_reads * 1000 / read_ms });

    db.close();
}
