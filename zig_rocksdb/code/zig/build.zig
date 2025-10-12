const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // 声明依赖 rocksdb
    const dep_rocksdb = b.dependency("rocksdb", .{
        .link_vendor = false, // 或 false，如果你希望使用系统已安装的 librocksdb
    });

    const exe = b.addExecutable(.{
        .name = "bench_rocksdb",
        .root_source_file = .{ .path = "bench_rocksdb.zig" },
        .target = target,
        .optimize = optimize,
    });

    // 导入 rocksdb 模块
    exe.root_module.addImport("rocksdb", dep_rocksdb.module("rocksdb"));

    // 链接依赖库
    exe.linkLibC();
    if (!dep_rocksdb.link_vendor) {
        exe.linkSystemLibrary("rocksdb");
    }
}
