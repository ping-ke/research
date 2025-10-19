const std = @import("std");
const clap = @import("clap");
const rocksdb = @import("rocksdb");

const DB = rocksdb.Database(.Multiple);
const valLen = 110;
const keyLen = 32;

var mutex = std.Thread.Mutex{};
var total: u64 = 0;
var init: u64 = 0;
var wc: u64 = 0;
var rc: u64 = 0;
var ver: u64 = 0;
var randBytes: [valLen * keyLen]u8 = undefined;

fn randomWriter(thid: usize, db: *DB, count: usize, start: usize, end: usize, wg: *std.Thread.WaitGroup) !void {
    defer wg.finish();
    var i: usize = 0;
    var timer = try std.time.Timer.start();
    var rng = std.rand.DefaultPrng.init(std.time.nanoTimestamp());
    var key: [keyLen]u8 = undefined;
    @memset(key[0..], 0);
    while (i < count) : (i += 1) {
        const rv = rng.randomLessThan(end - start) + start;
        const s = (rv % keyLen) * valLen;
        std.mem.writeInt(u64, key[keyLen - 8 .. keyLen], @byteSwap(rv), .little);
        try db.put(key[0..], randBytes[s .. s + valLen], .{});
        if (ver >= 3 and i % 100_000 == 0 and i > 0) {
            std.debug.print("thread {} used time {}ms, hps {}\n", .{ thid, timer.read() / 1_000_000, i * 1_000_000_000 / timer.read() });
        }
    }
    std.debug.print("thread {} written done used time {}ms, hps {}\n", .{ thid, timer.read() / 1_000_000, i * 1_000_000_000 / timer.read() });
}

fn randomReader(thid: usize, db: *DB, count: usize, start: usize, end: usize, wg: *std.Thread.WaitGroup) !void {
    defer wg.finish();
    var i: usize = 0;
    var timer = try std.time.Timer.start();
    var rng = std.rand.DefaultPrng.init(std.time.nanoTimestamp());
    var key: [valLen]u8 = undefined;
    @memset(key[0..], 0);
    while (i < count) : (i += 1) {
        const rv = rng.randomLessThan(end - start) + start;
        std.mem.writeInt(u64, key[keyLen - 8 .. keyLen], @byteSwap(rv), .little);
        _ = try db.get(key[0..], .{});
        if (ver >= 3 and i % 100_000 == 0 and i > 0) {
            std.debug.print("thread {} used time {}ms, hps {}\n", .{ thid, timer.read() / 1_000_000, i * 1_000_000_000 / timer.read() });
        }
    }
    std.debug.print("thread {} read done used time {}ms, hps {}\n", .{ thid, timer.read() / 1_000_000, i * 1_000_000_000 / timer.read() });
}

fn writer(thid: usize, db: *DB, count: usize, wg: *std.Thread.WaitGroup) !void {
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
        if (ver >= 3 and i % 100_000 == 0 and i > 0) {
            std.debug.print("thread {} used time {}ms, hps {}\n", .{ thid, timer.read() / 1_000_000, i * 1_000_000_000 / timer.read() });
        }
    }
    std.debug.print("thread {} written done used time {}ms, hps {}\n", .{ thid, timer.read() / 1_000_000, i * 1_000_000_000 / timer.read() });
}

fn reader(thid: usize, db: *DB, count: usize, wg: *std.Thread.WaitGroup) !void {
    defer wg.finish();
    var i: usize = 0;
    var timer = try std.time.Timer.start();
    var key: [valLen]u8 = undefined;
    @memset(key[0..], 0);
    while (i < count) : (i += 1) {
        std.mem.writeInt(u64, key[keyLen - 8 .. keyLen], @byteSwap(thid * count + i), .little);
        _ = try db.get(key[0..], .{});
        if (ver >= 3 and i % 100_000 == 0 and i > 0) {
            std.debug.print("thread {} used time {}ms, hps {}\n", .{ thid, timer.read() / 1_000_000, i * 1_000_000_000 / timer.read() });
        }
    }
    std.debug.print("thread {} read done used time {}ms, hps {}\n", .{ thid, timer.read() / 1_000_000, i * 1_000_000_000 / timer.read() });
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

    init = res.args.init orelse 0;
    total = res.args.total orelse 1_000_000_000;
    wc = res.args.write orelse 1_000_000;
    rc = res.args.read orelse 1_000_000;
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

    std.crypto.random.bytes(randBytes[0..]);

    if (init != 0) {
        // Init Write phase
        const per_i = total / tc;
        for (0..tc) |thid| {
            wg.start();
            _ = std.Thread.spawn(.{}, writer, .{ thid, &db, per_i, &wg }) catch unreachable;
        }
        wg.wait();
        const i_ms = @as(f64, @floatFromInt(timter.read())) / 1_000_000.0;
        std.debug.print("Init write: {d} ops in {d:.2} ms ({d:.2} ops/s)\n", .{ total, i_ms, @as(f64, @floatFromInt(total)) * 1000.0 / i_ms });

        wg.reset();
        timter.reset();
    }

    if (wc != 0) {
        // Random Write phase
        const per_w = wc / tc;
        for (0..tc) |thid| {
            wg.start();
            _ = std.Thread.spawn(.{}, randomWriter, .{ thid, &db, per_w, 0, total, &wg }) catch unreachable;
        }
        wg.wait();
        const w_ms = @as(f64, @floatFromInt(timter.read())) / 1_000_000.0;
        std.debug.print("write: {d} ops in {d:.2} ms ({d:.2} ops/s)\n", .{ wc, w_ms, @as(f64, @floatFromInt(wc)) * 1000.0 / w_ms });

        wg.reset();
        timter.reset();
    }

    if (rc != 0) {
        // Random Read phase
        const per_r = rc / tc;
        for (0..tc) |thid| {
            wg.start();
            _ = std.Thread.spawn(.{}, randomReader, .{ thid, &db, per_r, 0, total, &wg }) catch unreachable;
        }
        wg.wait();
        const r_ms = @as(f64, @floatFromInt(timter.read())) / 1_000_000.0;
        std.debug.print("Read: {d} ops in {d:.2} ms ({d:.2} ops/s)\n", .{ rc, r_ms, @as(f64, @floatFromInt(rc)) * 1000.0 / r_ms });
    }
}
