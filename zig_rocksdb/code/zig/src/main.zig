const std = @import("std");
const rocksdb = @cImport({
    @cInclude("rocksdb/c.h");
});

const valLen = 110;
const keyLen = 32;

var randBytes: [valLen * keyLen]u8 = undefined;

const Args = struct {
    needInit: bool = false,
    total: u64 = 4_000_000_000,
    writeCount: u64 = 10_000_000,
    readCount: u64 = 10_000_000,
    threads: usize = 8,
    batchInsert: bool = true,
    dbPath: []const u8 = "./data/bench_zig_rocksdb",
    logLevel: usize = 3,
};

fn fillRandBytes() void {
    var g = std.Random.DefaultPrng.init(@intCast(std.time.nanoTimestamp()));
    g.random().bytes(randBytes[0..]);
}

fn putKey(buf: []u8, v: u64) void {
    for (0..8) |i| buf[keyLen - 1 - i] = @intCast(u8, (v >> (i * 8)) & 0xFF);
}

fn batchWrite(thid: usize, count: usize, db: *rocksdb.rocksdb_t, args: *const Args) !void {
    var timer = try std.time.Timer.start();
    var key: [keyLen]u8 = undefined;
    @memset(key[0..], 0);

    const wopt = rocksdb.rocksdb_writeoptions_create();
    defer rocksdb.rocksdb_writeoptions_destroy(wopt);
    rocksdb.rocksdb_writeoptions_set_sync(wopt, 0);

    const batch = rocksdb.rocksdb_writebatch_create();
    defer rocksdb.rocksdb_writebatch_destroy(batch);

    var err: ?[*:0]const u8 = null;

    for (0..count) |i| {
        const idx: u64 = @intCast(thid * count + i);
        putKey(key[0..], idx);
        const s = (idx % keyLen) * valLen;
        rocksdb.rocksdb_writebatch_put(
            batch,
            key[0..keyLen].ptr,
            keyLen,
            &randBytes[s],
            valLen,
        );

        if (i % 1000 == 0) {
            rocksdb.rocksdb_write(db, wopt, batch, &err);
            if (err != null) {
                std.debug.print("batch write error: {s}\n", .{err.?});
                rocksdb.rocksdb_free(err.?);
                err = null;
            }
            rocksdb.rocksdb_writebatch_clear(batch);
        } else {
            continue;
        }

        if (args.logLevel >= 3 and i % 1_000_000 == 0 and i > 0) {
            const ms = timer.read() / 1_000_000;
            std.debug.print("thread {} used {} ms insert {}/{}\n", .{ thid, ms, i, count });
        }
    }

    if (rocksdb.rocksdb_writebatch_count(batch) > 0) {
        rocksdb.rocksdb_write(db, wopt, batch, &err);
        if (err != null) {
            std.debug.print("batch final err: {s}\n", .{err.?});
            rocksdb.rocksdb_free(err.?);
        }
    }

    const dur = @as(f64, @floatFromInt(timer.read())) / 1e9;
    std.debug.print("thread {} batch write done {:.2}s, {:.2} ops/s\n", .{ thid, dur, @as(f64, @floatFromInt(count)) / dur });
}

fn randomWrite(thid: usize, count: usize, start: usize, end: usize, db: *rocksdb.rocksdb_t, args: *const Args) !void {
    var timer = try std.time.Timer.start();
    var key: [keyLen]u8 = undefined;
    @memset(key[0..], 0);
    var g = std.Random.DefaultPrng.init(@intCast(std.time.nanoTimestamp()));
    const r = g.random();

    const wopt = rocksdb.rocksdb_writeoptions_create();
    defer rocksdb.rocksdb_writeoptions_destroy(wopt);
    rocksdb.rocksdb_writeoptions_set_sync(wopt, 0);

    var err: ?[*:0]const u8 = null;

    for (0..count) |i| {
        const rv = r.intRangeAtMost(usize, start, end);
        putKey(key[0..], rv);
        const s = (rv % keyLen) * valLen;
        rocksdb.rocksdb_put(
            db,
            wopt,
            key[0..keyLen].ptr,
            keyLen,
            &randBytes[s],
            valLen,
            &err,
        );
        if (err != null) {
            std.debug.print("random put err: {s}\n", .{err.?});
            rocksdb.rocksdb_free(err.?);
            err = null;
        }

        if (args.logLevel >= 3 and i % 1_000_000 == 0 and i > 0) {
            const ms = timer.read() / 1_000_000;
            std.debug.print("thread {} used {} ms randwrite {}/{}\n", .{ thid, ms, i, count });
        }
    }

    const dur = @as(f64, @floatFromInt(timer.read())) / 1e9;
    std.debug.print("thread {} random write done {:.2}s, {:.2} ops/s\n", .{ thid, dur, @as(f64, @floatFromInt(count)) / dur });
}

fn randomRead(thid: usize, count: usize, start: usize, end: usize, db: *rocksdb.rocksdb_t, args: *const Args) !void {
    var timer = try std.time.Timer.start();
    var key: [keyLen]u8 = undefined;
    @memset(key[0..], 0);
    var g = std.Random.DefaultPrng.init(@intCast(std.time.nanoTimestamp()));
    const r = g.random();

    const ropt = rocksdb.rocksdb_readoptions_create();
    defer rocksdb.rocksdb_readoptions_destroy(ropt);
    rocksdb.rocksdb_readoptions_set_verify_checksums(ropt, 0);
    rocksdb.rocksdb_readoptions_set_fill_cache(ropt, 0);

    var err: ?[*:0]const u8 = null;
    var vallen: usize = 0;

    for (0..count) |i| {
        const rv = r.intRangeAtMost(usize, start, end);
        putKey(key[0..], rv);
        const val_ptr = rocksdb.rocksdb_get(db, ropt, key[0..keyLen].ptr, keyLen, &vallen, &err);
        if (val_ptr != null) rocksdb.rocksdb_free(val_ptr);
        if (err != null) {
            std.debug.print("random read err: {s}\n", .{err.?});
            rocksdb.rocksdb_free(err.?);
            err = null;
        }

        if (args.logLevel >= 3 and i % 1_000_000 == 0 and i > 0) {
            const ms = timer.read() / 1_000_000;
            std.debug.print("thread {} used {} ms read {}/{}\n", .{ thid, ms, i, count });
        }
    }

    const dur = @as(f64, @floatFromInt(timer.read())) / 1e9;
    std.debug.print("thread {} random read done {:.2}s, {:.2} ops/s\n", .{ thid, dur, @as(f64, @floatFromInt(count)) / dur });
}

pub fn main() !void {
    // var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // const allocator = gpa.allocator();

    var args = Args{};
    const tc = args.threads;

    fillRandBytes();

    var err: [*c]u8 = null;

    // ---- RocksDB Options ----
    const opts = rocksdb.rocksdb_options_create();
    defer rocksdb.rocksdb_options_destroy(opts);
    rocksdb.rocksdb_options_set_create_if_missing(opts, 1);
    rocksdb.rocksdb_options_set_compression(opts, rocksdb.rocksdb_no_compression);
    rocksdb.rocksdb_options_set_compaction_style(opts, rocksdb.rocksdb_universal_compaction);
    rocksdb.rocksdb_options_set_max_open_files(opts, 512);
    rocksdb.rocksdb_options_set_write_buffer_size(opts, 64 << 20);
    rocksdb.rocksdb_options_set_max_write_buffer_number(opts, 3);
    rocksdb.rocksdb_options_set_target_file_size_base(opts, 32 << 20);
    rocksdb.rocksdb_options_set_max_bytes_for_level_base(opts, 256 << 20);
    rocksdb.rocksdb_options_increase_parallelism(opts, @intCast(tc));

    const table_opts = rocksdb.rocksdb_block_based_options_create();
    defer rocksdb.rocksdb_block_based_options_destroy(table_opts);
    const cache = rocksdb.rocksdb_cache_create_lru(128 << 20);
    rocksdb.rocksdb_block_based_options_set_block_cache(table_opts, cache);
    rocksdb.rocksdb_options_set_block_based_table_factory(opts, table_opts);

    const db = rocksdb.rocksdb_open(opts, args.dbPath.ptr, &err);
    if (err != null) {
        std.debug.print("open db error: {s}\n", .{err.?});
        rocksdb.rocksdb_free(err.?);
        return;
    }
    defer rocksdb.rocksdb_close(db);

    var wg = std.Thread.WaitGroup{};
    var timer = try std.time.Timer.start();
    // ---- Init Write ----
    if (args.needInit and args.total > 0) {
        const per = args.total / tc;
        for (0..tc) |thid| {
            wg.start();
            _ = std.Thread.spawn(.{}, batchWrite, .{ thid, per, db, &args }) catch unreachable;
        }
        wg.wait();
        const dur_ms = @as(f64, @floatFromInt(timer.read())) / 1_000_000.0;
        std.debug.print("Init write: {} ops in {:.2} ms ({:.2} ops/s)\n", .{
            args.total, dur_ms, @as(f64, @floatFromInt(args.total)) * 1000.0 / dur_ms,
        });

        wg.reset();
        timer.reset();
    }

    // ---- Random Write ----
    if (args.writeCount > 0) {
        const per = args.writeCount / tc;
        for (0..tc) |thid| {
            wg.start();
            _ = std.Thread.spawn(.{}, randomWrite, .{ thid, per, 0, args.total, db, &args }) catch unreachable;
        }
        wg.wait();
        const dur_ms = @as(f64, @floatFromInt(timer.read())) / 1_000_000.0;
        std.debug.print("Random update: {} ops in {:.2} ms ({:.2} ops/s)\n", .{
            args.writeCount, dur_ms, @as(f64, @floatFromInt(args.writeCount)) * 1000.0 / dur_ms,
        });

        wg.reset();
        timer.reset();
    }

    // ---- Random Read ----
    if (args.readCount > 0) {
        const per = args.readCount / tc;
        for (0..tc) |thid| {
            wg.start();
            _ = std.Thread.spawn(.{}, randomRead, .{ thid, per, 0, args.total, db, &args }) catch unreachable;
        }
        wg.wait();
        const dur_ms = @as(f64, @floatFromInt(timer.read())) / 1_000_000.0;
        std.debug.print("Random read: {} ops in {:.2} ms ({:.2} ops/s)\n", .{
            args.readCount, dur_ms, @as(f64, @floatFromInt(args.readCount)) * 1000.0 / dur_ms,
        });
    }
}
