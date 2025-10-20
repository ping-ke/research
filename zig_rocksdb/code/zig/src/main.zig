const std = @import("std");
const clap = @import("clap");
const rocksdb = @cImport({
    @cInclude("rocksdb/c.h");
});

const valLen = 110;
const keyLen = 32;
const dbPath = "/tmp/zig-rocksdb-mt";

var randBytes: [valLen * keyLen]u8 = undefined;

var total: u64 = 0;
var needInit: bool = false;
var wc: u64 = 0;
var rc: u64 = 0;
var ver: u64 = 0;

fn fillRandBytes() void {
    var g = std.Random.DefaultPrng.init(@intCast(std.time.nanoTimestamp()));
    g.random().bytes(randBytes[0..]);
}

fn batchWrite(thid: usize, count: usize, db: *rocksdb.rocksdb_t) !void {
    var timer = try std.time.Timer.start();
    var key: [keyLen]u8 = undefined;
    @memset(key[0..], 0);

    const wopt = rocksdb.rocksdb_writeoptions_create();
    defer rocksdb.rocksdb_writeoptions_destroy(wopt);
    rocksdb.rocksdb_writeoptions_set_sync(wopt, 0);

    const batch = rocksdb.rocksdb_writebatch_create();
    defer rocksdb.rocksdb_writebatch_destroy(batch);

    var err: [*c]u8 = null;

    for (0..count) |i| {
        const idx: u64 = @intCast(thid * count + i);
        std.mem.writeInt(u64, key[keyLen - 8 .. keyLen], @byteSwap(idx), .little);
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

        if (ver >= 3 and i % 1_000_000 == 0 and i > 0) {
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

fn randomWrite(thid: usize, count: usize, start: usize, end: usize, db: *rocksdb.rocksdb_t) !void {
    var timer = try std.time.Timer.start();
    var key: [keyLen]u8 = undefined;
    @memset(key[0..], 0);
    var g = std.Random.DefaultPrng.init(@intCast(std.time.nanoTimestamp()));
    const r = g.random();

    const wopt = rocksdb.rocksdb_writeoptions_create();
    defer rocksdb.rocksdb_writeoptions_destroy(wopt);
    rocksdb.rocksdb_writeoptions_set_sync(wopt, 0);

    var err: [*c]u8 = null;

    for (0..count) |i| {
        const rv = r.intRangeAtMost(usize, start, end);
        std.mem.writeInt(u64, key[keyLen - 8 .. keyLen], @byteSwap(rv), .little);
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

        if (ver >= 3 and i % 1_000_000 == 0 and i > 0) {
            const ms = timer.read() / 1_000_000;
            std.debug.print("thread {} used {} ms randwrite {}/{}\n", .{ thid, ms, i, count });
        }
    }

    const dur = @as(f64, @floatFromInt(timer.read())) / 1e9;
    std.debug.print("thread {} random write done {:.2}s, {:.2} ops/s\n", .{ thid, dur, @as(f64, @floatFromInt(count)) / dur });
}

fn randomRead(thid: usize, count: usize, start: usize, end: usize, db: *rocksdb.rocksdb_t) !void {
    var timer = try std.time.Timer.start();
    var key: [keyLen]u8 = undefined;
    @memset(key[0..], 0);
    var g = std.Random.DefaultPrng.init(@intCast(std.time.nanoTimestamp()));
    const r = g.random();

    const ropt = rocksdb.rocksdb_readoptions_create();
    defer rocksdb.rocksdb_readoptions_destroy(ropt);
    rocksdb.rocksdb_readoptions_set_verify_checksums(ropt, 0);
    rocksdb.rocksdb_readoptions_set_fill_cache(ropt, 0);

    var err: [*c]u8 = null;
    var vallen: usize = 0;

    for (0..count) |i| {
        const rv = r.intRangeAtMost(usize, start, end);
        std.mem.writeInt(u64, key[keyLen - 8 .. keyLen], @byteSwap(rv), .little);
        const val_ptr = rocksdb.rocksdb_get(db, ropt, key[0..keyLen].ptr, keyLen, &vallen, &err);
        if (val_ptr != null) rocksdb.rocksdb_free(val_ptr);
        if (err != null) {
            std.debug.print("random read err: {s}\n", .{err.?});
            rocksdb.rocksdb_free(err.?);
            err = null;
        }

        if (ver >= 3 and i % 1_000_000 == 0 and i > 0) {
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
    const allocator = std.heap.page_allocator;

    // First we specify what parameters our program can take.
    // We can use `parseParamsComptime` to parse a string into an array of `Param(Help)`.
    const params = comptime clap.parseParamsComptime(
        \\-h, --help              Display this help and exit.
        \\-i, --init <u64>        Need to insert kvs before test, default 0 means already have data in the db.
        \\-T, --total <u64>       Number of kvs to insert before test, default value is 1_000_000_000.
        \\-w, --write <u64>       Number of write during the test.
        \\-r, --read <u64>        Number of read count during the test.
        \\-v, --verbosity <u64>   Verbosity.
        \\-t, --thread <u64>      Number of threads.
    );
    // Initialize our diagnostics, which can be used for reporting useful errors.
    // This is optional. You can also pass `.{}` to `clap.parse` if you don't
    // care about the extra information `Diagnostic` provides.
    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, clap.parsers.default, .{
        .diagnostic = &diag,
        .allocator = allocator,
    }) catch |err| {
        // Report useful error and exit.
        try diag.reportToFile(.stderr(), err);
        return err;
    };
    defer res.deinit();

    const init = res.args.init orelse 0;
    needInit = init == 0;
    total = res.args.total orelse 4_000_000_000;
    wc = res.args.write orelse 10_000_000;
    rc = res.args.read orelse 10_000_000;
    ver = res.args.verbosity orelse 3;
    const tc = res.args.thread orelse 8;

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

    const db_opt = rocksdb.rocksdb_open(opts, dbPath.ptr, &err);
    if (db_opt == null) {
        std.debug.print("Failed to open RocksDB: {s}\n", .{err.?});
        return error.OpenFailed;
    }
    const db = db_opt.?;
    defer rocksdb.rocksdb_close(db);

    var wg = std.Thread.WaitGroup{};
    var timer = try std.time.Timer.start();
    // ---- Init Write ----
    if (needInit and total > 0) {
        const per = total / tc;
        for (0..tc) |thid| {
            wg.start();
            _ = std.Thread.spawn(.{}, batchWrite, .{ thid, per, db }) catch unreachable;
        }
        wg.wait();
        const dur_ms = @as(f64, @floatFromInt(timer.read())) / 1_000_000.0;
        std.debug.print("Init write: {} ops in {:.2} ms ({:.2} ops/s)\n", .{
            total, dur_ms, @as(f64, @floatFromInt(total)) * 1000.0 / dur_ms,
        });

        wg.reset();
        timer.reset();
    }

    // ---- Random Write ----
    if (wc > 0) {
        const per = wc / tc;
        for (0..tc) |thid| {
            wg.start();
            _ = std.Thread.spawn(.{}, randomWrite, .{ thid, per, 0, total, db }) catch unreachable;
        }
        wg.wait();
        const dur_ms = @as(f64, @floatFromInt(timer.read())) / 1_000_000.0;
        std.debug.print("Random update: {} ops in {:.2} ms ({:.2} ops/s)\n", .{
            wc, dur_ms, @as(f64, @floatFromInt(wc)) * 1000.0 / dur_ms,
        });

        wg.reset();
        timer.reset();
    }

    // ---- Random Read ----
    if (rc > 0) {
        const per = rc / tc;
        for (0..tc) |thid| {
            wg.start();
            _ = std.Thread.spawn(.{}, randomRead, .{ thid, per, 0, total, db }) catch unreachable;
        }
        wg.wait();
        const dur_ms = @as(f64, @floatFromInt(timer.read())) / 1_000_000.0;
        std.debug.print("Random read: {} ops in {:.2} ms ({:.2} ops/s)\n", .{
            rc, dur_ms, @as(f64, @floatFromInt(rc)) * 1000.0 / dur_ms,
        });
    }
}
