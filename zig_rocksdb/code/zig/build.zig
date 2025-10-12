const std = @import("std");

pub fn build(b: *std.Build) void {
    // Define target and optimization mode
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Define the executable target
    const exe = b.addExecutable(.{
        .name = "bench_rocksdb",
        .root_source_file = b.path("zig-rocksdb-mt.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add dependency: jiacai2050/zig-rocksdb
    const dep_rocksdb = b.dependency("rocksdb", .{
        .path = "../../../../zig-rocksdb", // ← 本地克隆路径
        // Use the vendored (static) version of RocksDB included in zig-rocksdb
        .link_vendor = false,
    });

    exe.root_module.addImport("rocksdb", dep_rocksdb.module("rocksdb"));
    exe.linkLibrary(dep_rocksdb.artifact("rocksdb"));

    // Link system libs for RocksDB
    exe.linkSystemLibrary("pthread");
    exe.linkSystemLibrary("stdc++");
    exe.linkSystemLibrary("z"); // compression
    exe.linkSystemLibrary("bz2"); // bzip2 compression
    exe.linkSystemLibrary("lz4"); // lz4 compression
    exe.linkSystemLibrary("snappy"); // snappy compression
    exe.linkSystemLibrary("zstd"); // zstd compression

    // Define the "run" step (so `zig build run` works)
    const run_cmd = b.addRunArtifact(exe);
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the RocksDB benchmark");
    run_step.dependOn(&run_cmd.step);

    // Install the executable
    b.installArtifact(exe);
}
