const std = @import("std");
const clap = @import("clap");
const rocksdb = @import("rocksdb");

const keyprefix: [4]u8 = [_]u8{ 'k', 'e', 'y', '-' };
const valprefix: [4]u8 = [_]u8{ 'v', 'a', 'l', '-' };
const seed: u64 = @intCast(std.time.nanoTimestamp());
const random = std.rand.DefaultPrng.init(seed).random();

var mutex = std.Thread.Mutex{};
var init: u64 = 0;
var wc: u64 = 0;
var rc: u64 = 0;
var ver: u64 = 0;

pub fn makebytes(prefix: [4]u8, i: u64, len: u64) []u8 {
    var bs: [len]u8 = undefined;
    @memset(&bs, 0);
    bs[0..4].* = prefix;
    std.mem.bytesAsValue(u64, bs[len - 8]).* = @byteSwap(i);
    return bs;
}

fn randomWriter(thid: usize, db: *rocksdb.DB, allocator: std.mem.Allocator, count: usize, start: usize, end: usize, wg: *std.Thread.WaitGroup) void {
    defer wg.finish();
    var i: usize = 0;
    var timer = try std.time.Timer.start();
    while (i < count) : (i += 1) {
        const val = random.intRange(usize, start, end);
        const key = makebytes(keyprefix, val, 32);
        defer allocator.free(key);
        const value = makebytes(valprefix, val, 110);
        defer allocator.free(value);
        try db.put(key, value, .{});
        if (ver >= 3 and i % 10_000 == 0) {
            std.debug.print("thread {} used time {}ns, hps {}\n", .{ thid, timer.read(), val / timer.read() });
        }
    }
    std.debug.print("thread {} written done used time {}ns, hps {}\n", .{ thid, timer.read(), i / timer.read() });
}

fn randomReader(thid: usize, db: *rocksdb.DB, allocator: std.mem.Allocator, count: usize, start: usize, end: usize, wg: *std.Thread.WaitGroup) void {
    defer wg.finish();
    var i: usize = 0;
    var timer = try std.time.Timer.start();
    while (i < count) : (i += 1) {
        const val = random.intRange(usize, start, end);
        const key = makebytes(keyprefix, val, 32);
        defer allocator.free(key);
        try db.get(key, .{});
        if (ver >= 3 and i % 10_000 == 0) {
            std.debug.print("thread {} used time {}ns, hps {}\n", .{ thid, timer.read(), i / timer.read() });
        }
    }
    std.debug.print("thread {} read done used time {}ns, hps {}\n", .{ thid, timer.read(), i / timer.read() });
}

fn writer(thid: usize, db: *rocksdb.DB, allocator: std.mem.Allocator, count: usize, wg: *std.Thread.WaitGroup) void {
    defer wg.finish();
    var i: usize = 0;
    var timer = try std.time.Timer.start();
    while (i < count) : (i += 1) {
        const key = makebytes(keyprefix, i, 32);
        defer allocator.free(key);
        const value = makebytes(valprefix, i, 110);
        defer allocator.free(value);
        try db.put(key, value, .{});
        if (ver >= 3 and i % 10_000 == 0) {
            std.debug.print("thread {} used time {}ns, hps {}\n", .{ thid, timer.read(), i / timer.read() });
        }
    }
    std.debug.print("thread {} written done used time {}ns, hps {}\n", .{ thid, timer.read(), i / timer.read() });
}

fn reader(thid: usize, db: *rocksdb.DB, allocator: std.mem.Allocator, count: usize, wg: *std.Thread.WaitGroup) void {
    defer wg.finish();
    var i: usize = 0;
    var timer = try std.time.Timer.start();
    while (i < count) : (i += 1) {
        const key = makebytes(keyprefix, i, 32);
        defer allocator.free(key);
        try db.get(key, .{});
        if (ver >= 3 and i % 10_000 == 0) {
            std.debug.print("thread {} used time {}ns, hps {}\n", .{ thid, timer.read(), i / timer.read() });
        }
    }
    std.debug.print("thread {} read done used time {}ns, hps {}\n", .{ thid, timer.read(), i / timer.read() });
}

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();

    // First we specify what parameters our program can take.
    // We can use `parseParamsComptime` to parse a string into an array of `Param(Help)`.
    const params = comptime clap.parseParamsComptime(
        \\-h, --help              Display this help and exit.
        \\-i, --init <u64>        Number of kv to insert before test, default 0 means already have data in the db.
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
        .allocator = gpa.allocator(),
    }) catch |err| {
        // Report useful error and exit.
        try diag.reportToFile(.stderr(), err);
        return err;
    };
    defer res.deinit();

    init = res.args.init orelse 0;
    wc = res.args.write orelse 1000000;
    rc = res.args.read orelse 1000000;
    ver = res.args.verbosity orelse 3;
    const tc = res.args.thread orelse 1;

    var db = try rocksdb.Database(.Single).open(
        gpa,
        "/tmp/zig-rocksdb-mt",
        .{
            .create_if_missing = true,
        },
    );

    var timter = try std.time.Timer.start();
    var wg = std.Thread.WaitGroup.init(tc);

    // Init Write phase
    const per_i = init + wc / tc;
    for (tc) |thid| {
        _ = std.Thread.spawn(.{}, writer, .{ thid, &db, gpa, per_i, &wg }) catch unreachable;
    }
    wg.wait();
    const i_ms = @as(f64, @floatFromInt(timter.read())) / 1_000_000.0;
    std.debug.print("Init write: {d} ops in {d:.2} ms ({d:.2} ops/s)\n", .{ wc, i_ms, wc * 1000 / i_ms });

    // Random Write phase
    wg.reset(tc);
    timter.reset();

    const per_w = wc / tc;
    for (tc) |thid| {
        _ = std.Thread.spawn(.{}, randomWriter, .{ thid, &db, gpa, per_w, 0, wc + init, &wg }) catch unreachable;
    }
    wg.wait();
    const w_ms = @as(f64, @floatFromInt(timter.read())) / 1_000_000.0;
    std.debug.print("Init write: {d} ops in {d:.2} ms ({d:.2} ops/s)\n", .{ wc, w_ms, wc * 1000 / w_ms });

    // Random Read phase
    wg.reset(tc);
    timter.reset();

    const per_r = rc / tc;
    for (tc) |thid| {
        _ = std.Thread.spawn(.{}, randomReader, .{ thid, &db, gpa, per_r, 0, wc + init, &wg }) catch unreachable;
    }
    wg.wait();
    const r_ms = @as(f64, @floatFromInt(timter.read())) / 1_000_000.0;
    std.debug.print("Read: {d} ops in {d:.2} ms ({d:.2} ops/s)\n", .{ rc, r_ms, rc * 1000 / r_ms });

    std.debug.print("used time {}ns, hps {}\n", .{ timter.read(), 1000_000_000 * init / timter.read() });
}
