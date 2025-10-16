const std = @import("std");
const clap = @import("clap");
const rocksdb = @import("rocksdb");

const keyprefix: [4]u8 = [_]u8{ 'k', 'e', 'y', '-' };
const valprefix: [4]u8 = [_]u8{ 'v', 'a', 'l', '-' };
const seed: u64 = @intCast(std.time.nanoTimestamp());
const DB = rocksdb.Database(.Multiple);

var rand = std.Random.DefaultPrng.init(seed);
var mutex = std.Thread.Mutex{};
var init: u64 = 0;
var wc: u64 = 0;
var rc: u64 = 0;
var ver: u64 = 0;

pub fn makebytes(allocator: std.mem.Allocator, prefix: [4]u8, i: u64, len: u64) ![]u8 {
    var bs = try allocator.alloc(u8, len);
    std.mem.set(u8, bs, 0);
    std.mem.copy(u8, bs[0..4], prefix[0..]);
    std.mem.writeInt(u64, bs[len - 8 .. len], @byteSwap(i), .little);
    return bs;
}

fn randomWriter(thid: usize, db: *DB, allocator: std.mem.Allocator, count: usize, start: usize, end: usize, wg: *std.Thread.WaitGroup) !void {
    defer wg.finish();
    var i: usize = 0;
    var timer = try std.time.Timer.start();
    while (i < count) : (i += 1) {
        const val = rand.intRangeLessThan(usize, start, end);
        const key = makebytes(allocator, keyprefix, val, 32);
        defer allocator.free(key);
        const value = makebytes(allocator, valprefix, val, 110);
        defer allocator.free(value);
        try db.put(key, value, .{});
        if (ver >= 3 and i % 10_000 == 0) {
            std.debug.print("thread {} used time {}ns, hps {}\n", .{ thid, timer.read(), val / timer.read() });
        }
    }
    std.debug.print("thread {} written done used time {}ns, hps {}\n", .{ thid, timer.read(), i / timer.read() });
}

fn randomReader(thid: usize, db: *DB, allocator: std.mem.Allocator, count: usize, start: usize, end: usize, wg: *std.Thread.WaitGroup) !void {
    defer wg.finish();
    var i: usize = 0;
    var timer = try std.time.Timer.start();
    while (i < count) : (i += 1) {
        const val = rand.intRangeLessThan(usize, start, end);
        const key = makebytes(allocator, keyprefix, val, 32);
        defer allocator.free(key);
        try db.get(key, .{});
        if (ver >= 3 and i % 10_000 == 0) {
            std.debug.print("thread {} used time {}ns, hps {}\n", .{ thid, timer.read(), i / timer.read() });
        }
    }
    std.debug.print("thread {} read done used time {}ns, hps {}\n", .{ thid, timer.read(), i / timer.read() });
}

fn writer(thid: usize, db: *DB, allocator: std.mem.Allocator, count: usize, wg: *std.Thread.WaitGroup) !void {
    defer wg.finish();
    var i: usize = 0;
    var timer = try std.time.Timer.start();
    while (i < count) : (i += 1) {
        const key = makebytes(allocator, keyprefix, thid * count + i, 32);
        defer allocator.free(key);
        const value = makebytes(allocator, valprefix, i, 110);
        defer allocator.free(value);
        try db.put(key, value, .{});
        if (ver >= 3 and i % 10_000 == 0) {
            std.debug.print("thread {} used time {}ns, hps {}\n", .{ thid, timer.read(), i / timer.read() });
        }
    }
    std.debug.print("thread {} written done used time {}ns, hps {}\n", .{ thid, timer.read(), i / timer.read() });
}

fn reader(thid: usize, db: *DB, allocator: std.mem.Allocator, count: usize, wg: *std.Thread.WaitGroup) !void {
    defer wg.finish();
    var i: usize = 0;
    var timer = try std.time.Timer.start();
    while (i < count) : (i += 1) {
        const key = makebytes(allocator, keyprefix, i, 32);
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
    const allocator = gpa.allocator();
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
        .allocator = allocator,
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

    var db = try DB.open(
        allocator,
        "/tmp/zig-rocksdb-mt",
        .{
            .create_if_missing = true,
        },
    );

    var timter = try std.time.Timer.start();
    var wg: std.Thread.WaitGroup = .{};

    // Init Write phase
    const per_i = (init + wc) / tc;
    for (0..tc) |thid| {
        wg.start();
        _ = std.Thread.spawn(.{}, writer, .{ thid, &db, allocator, per_i, &wg }) catch unreachable;
    }
    wg.wait();
    const i_ms = @as(f64, @floatFromInt(timter.read())) / 1_000_000.0;
    std.debug.print("Init write: {d} ops in {d:.2} ms ({d:.2} ops/s)\n", .{ init + wc, i_ms, @as(f64, @floatFromInt(init + wc)) * 1000.0 / i_ms });

    // Random Write phase
    wg.reset();
    timter.reset();

    const per_w = wc / tc;
    for (0..tc) |thid| {
        wg.start();
        _ = std.Thread.spawn(.{}, randomWriter, .{ thid, &db, allocator, per_w, 0, wc + init, &wg }) catch unreachable;
    }
    wg.wait();
    const w_ms = @as(f64, @floatFromInt(timter.read())) / 1_000_000.0;
    std.debug.print("write: {d} ops in {d:.2} ms ({d:.2} ops/s)\n", .{ wc, w_ms, @as(f64, @floatFromInt(wc)) * 1000.0 / w_ms });

    // Random Read phase
    wg.reset();
    timter.reset();

    const per_r = rc / tc;
    for (0..tc) |thid| {
        wg.start();
        _ = std.Thread.spawn(.{}, randomReader, .{ thid, &db, allocator, per_r, 0, wc + init, &wg }) catch unreachable;
    }
    wg.wait();
    const r_ms = @as(f64, @floatFromInt(timter.read())) / 1_000_000.0;
    std.debug.print("Read: {d} ops in {d:.2} ms ({d:.2} ops/s)\n", .{ rc, r_ms, @as(f64, @floatFromInt(rc)) * 1000.0 / r_ms });

    std.debug.print("used time {}ns, hps {}\n", .{ timter.read(), 1000_000_000 * init / timter.read() });
}
