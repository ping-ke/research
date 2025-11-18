const std = @import("std");
const clap = @import("clap");
const rocksdb = @import("rocksdb");

const DB = rocksdb.Database(.Multiple);
const valLen = 110;
const keyLen = 32;

var total: u64 = 0;
var needInit: bool = false;
var writeCount: u64 = 0;
var readCount: u64 = 0;
var verbosity: u64 = 0;
var randBytes: [valLen * keyLen]u8 = undefined;

fn randomWrite(thid: usize, db: *DB, count: usize, start: usize, end: usize, wg: *std.Thread.WaitGroup) !void {
    defer wg.finish();
    var i: usize = 0;
    var timer = try std.time.Timer.start();
    var g = std.Random.DefaultPrng.init(@intCast(std.time.nanoTimestamp()));
    const r = g.random();
    var key: [keyLen]u8 = undefined;
    @memset(key[0..], 0);
    while (i < count) : (i += 1) {
        const rv = r.intRangeAtMost(usize, start, end);
        const s = (rv % keyLen) * valLen;
        std.mem.writeInt(u64, key[keyLen - 8 .. keyLen], @byteSwap(rv), .little);
        try db.put(key[0..], randBytes[s .. s + valLen], .{});
        if (verbosity >= 3 and i % 1_000_000 == 0 and i > 0) {
            std.debug.print("thread {} used time {}ms, hps {}\n", .{ thid, timer.read() / 1_000_000, i * 1_000_000_000 / timer.read() });
        }
    }
    if (verbosity >= 3) {
        std.debug.print("thread {} written done used time {}ms, hps {}\n", .{ thid, timer.read() / 1_000_000, i * 1_000_000_000 / timer.read() });
    }
}

fn randomRead(thid: usize, buf: []u8, count: usize, db: *DB, wg: *std.Thread.WaitGroup) !void {
    defer wg.finish();
    var i: usize = 0;
    var timer = try std.time.Timer.start();
    while (i < count) : (i += 1) {
        const key = buf[i * keyLen .. (i + 1) * keyLen];
        _ = try db.get(key, .{ .verify_checksums = true });
        if (verbosity >= 3 and i % 1_000_000 == 0 and i > 0) {
            std.debug.print("thread {} used time {}ms, hps {}\n", .{ thid, timer.read() / 1_000_000, i * 1_000_000_000 / timer.read() });
        }
    }
    if (verbosity >= 3) {
        std.debug.print("thread {} read done used time {}ms, hps {}\n", .{ thid, timer.read() / 1_000_000, i * 1_000_000_000 / timer.read() });
    }
}

fn seqWrite(thid: usize, db: *DB, count: usize, wg: *std.Thread.WaitGroup) !void {
    defer wg.finish();
    var i: usize = 0;
    var timer = try std.time.Timer.start();
    var key: [keyLen]u8 = undefined;
    @memset(key[0..], 0);
    while (i < count) : (i += 1) {
        const idx = thid * count + i;
        const s = (idx % keyLen) * valLen;
        std.mem.writeInt(u64, key[keyLen - 8 .. keyLen], @byteSwap(idx), .little);
        try db.put(key[0..], randBytes[s .. s + valLen], .{});
        if (verbosity >= 3 and i % 1_000_000 == 0 and i > 0) {
            std.debug.print("thread {} used time {}ms, hps {}\n", .{ thid, timer.read() / 1_000_000, i * 1_000_000_000 / timer.read() });
        }
    }
    if (verbosity >= 3) {
        std.debug.print("thread {} written done used time {}ms, hps {}\n", .{ thid, timer.read() / 1_000_000, i * 1_000_000_000 / timer.read() });
    }
}

pub fn main() !void {
    // var gpa = std.heap.DebugAllocator(.{}){};
    // const allocator = gpa.allocator();
    // defer _ = gpa.deinit();
    const allocator = std.heap.page_allocator;

    // First we specify what parameters our program can take.
    // We can use `parseParamsComptime` to parse a string into an array of `Param(Help)`.
    const params = comptime clap.parseParamsComptime(
        \\-h, --help              Display this help and exit.
        \\-i, --init <u64>        Need to insert kvs before test, default 0 means already have data in the db.
        \\-T, --total <u64>       Number of kvs to insert before test, default value is 4_000_000_000.
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
    needInit = init != 0;
    total = res.args.total orelse 4_000_000_000;
    writeCount = res.args.write orelse 10_000_000;
    readCount = res.args.read orelse 10_000_000;
    verbosity = res.args.verbosity orelse 3;
    const threads = res.args.thread orelse 32;

    var db = try DB.open(
        allocator,
        "./data/bench_zig_rocksdb",
        .{ .create_if_missing = true, .max_open_files = 100000, .max_file_opening_threads = -1 },
    );

    std.debug.print("Threads: {}\n", .{threads});
    std.debug.print("Total data: {} while needInit={}\n", .{ total, needInit });
    std.debug.print("Ops: {} write ops and {} read ops\n", .{ writeCount, readCount });

    var g = std.Random.DefaultPrng.init(@intCast(std.time.nanoTimestamp()));
    g.random().bytes(randBytes[0..]);

    if (init != 0) {
        // Init Write phase
        var wg: std.Thread.WaitGroup = .{};
        var timer = try std.time.Timer.start();
        const per_i = total / threads;
        for (0..threads) |thid| {
            wg.start();
            _ = std.Thread.spawn(.{}, seqWrite, .{ thid, &db, per_i, &wg }) catch unreachable;
        }
        wg.wait();
        const i_ms = @as(f64, @floatFromInt(timer.read())) / 1_000_000.0;
        std.debug.print("Init write: {d} ops in {d:.2} ms ({d:.2} ops/s)\n", .{ total, i_ms, @as(f64, @floatFromInt(total)) * 1000.0 / i_ms });
    }

    if (writeCount != 0) {
        // Random Write phase
        var timer = try std.time.Timer.start();
        var wg: std.Thread.WaitGroup = .{};
        const per_w = writeCount / threads;
        for (0..threads) |thid| {
            wg.start();
            _ = std.Thread.spawn(.{}, randomWrite, .{ thid, &db, per_w, 0, total, &wg }) catch unreachable;
        }
        wg.wait();
        const w_ms = @as(f64, @floatFromInt(timer.read())) / 1_000_000.0;
        std.debug.print("write: {d} ops in {d:.2} ms ({d:.2} ops/s)\n", .{ writeCount, w_ms, @as(f64, @floatFromInt(writeCount)) * 1000.0 / w_ms });
    }

    if (readCount != 0) {
        const per = readCount / threads;

        // ---------- Step 1: 预生成所有随机 keys ----------
        var rng = std.Random.DefaultPrng.init(@intCast(std.time.nanoTimestamp()));
        const r = rng.random();

        // 分配一个二维数组: [threads][per * keyLen]
        var thread_keys = try allocator.alloc([]u8, threads);
        defer {
            for (thread_keys) |buf| allocator.free(buf);
            allocator.free(thread_keys);
        }

        for (0..threads) |thid| {
            const buf = try allocator.alloc(u8, per * keyLen);
            @memset(buf, 0);

            for (0..per) |i| {
                const rv = r.intRangeAtMost(usize, 0, total);
                const dest = buf[i * keyLen + keyLen - 8 .. (i + 1) * keyLen];
                std.mem.copyForwards(u8, dest, std.mem.asBytes(&@byteSwap(rv)));
            }

            thread_keys[thid] = buf;
        }
        if (verbosity >= 3) {
            std.debug.print("Keys generation done.\n", .{});
        }

        var timer = try std.time.Timer.start();
        var wg: std.Thread.WaitGroup = .{};
        for (0..threads) |thid| {
            wg.start();
            const buf = thread_keys[thid]; // []u8
            _ = std.Thread.spawn(.{}, randomRead, .{ thid, buf, per, &db, &wg }) catch unreachable;
        }

        wg.wait();
        const r_ms = @as(f64, @floatFromInt(timer.read())) / 1_000_000.0;
        std.debug.print("Read: {d} ops in {d:.2} ms ({d:.2} ops/s)\n", .{ readCount, r_ms, @as(f64, @floatFromInt(readCount)) * 1000.0 / r_ms });
    }
}
