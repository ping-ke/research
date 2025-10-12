const std = @import("std");
const rocksdb = @import("rocksdb");

fn random_bytes(allocator: std.mem.Allocator, len: usize) []u8 {
    var buf = allocator.alloc(u8, len) catch unreachable;
    var prng = std.rand.DefaultPrng.init(@intCast(u64, std.time.timestamp()));
    var r = prng.random();
    for (buf) |*b| b.* = r.int(u8);
    return buf;
}

fn writer(db: *rocksdb.DB, allocator: std.mem.Allocator, count: usize) void {
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const key = random_bytes(allocator, 32);
        const value = random_bytes(allocator, 110);
        _ = db.put(key, value) catch {};
        allocator.free(key);
        allocator.free(value);
    }
}

fn reader(db: *rocksdb.DB, allocator: std.mem.Allocator, count: usize) void {
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const key = random_bytes(allocator, 32);
        _ = db.get(key) catch {};
        allocator.free(key);
    }
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const total_keys = 100_000;
    const sample_reads = 10_000;
    const threads: usize = 8;

    var opts = rocksdb.Options{};
    opts.create_if_missing = true;
    opts.compression = .no_compression;
    var db = try rocksdb.DB.open(opts, "zig-rocksdb-mt");

    const per_thread = total_keys / threads;
    var t = try std.time.Timer.start();

    var wg = std.Thread.WaitGroup{};
    wg.init(threads);
    for (threads) |i| {
        _ = std.Thread.spawn(.{}, writer, .{ &db, allocator, per_thread }) catch unreachable;
    }
    wg.wait();
    const w_ms = @as(f64, @floatFromInt(t.read())) / 1_000_000.0;
    std.debug.print("Write: {d} ops in {d:.2} ms ({d:.2} ops/s)\n", .{ total_keys, w_ms, total_keys * 1000 / w_ms });

    // Read phase
    t.reset();
    wg.init(threads);
    const per_r = sample_reads / threads;
    for (threads) |_| {
        _ = std.Thread.spawn(.{}, reader, .{ &db, allocator, per_r }) catch unreachable;
    }
    wg.wait();
    const r_ms = @as(f64, @floatFromInt(t.read())) / 1_000_000.0;
    std.debug.print("Read: {d} ops in {d:.2} ms ({d:.2} ops/s)\n", .{ sample_reads, r_ms, sample_reads * 1000 / r_ms });

    db.close();
}
