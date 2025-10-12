const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Create executable
    const exe = b.addExecutable(.{
        .name = "bench_rocksdb",
        .root_module = b.addModule("root", .{
            .root_source_file = b.path("zig-rocksdb-mt.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Add dependency: jiacai2050/zig-rocksdb
    const dep_rocksdb = b.dependency("rocksdb", .{
        // Use local version of jiacai2050/zig-rocksdb to fix build error
        .path = "../../../../zig-rocksdb",
        // Use the vendored (static) version of RocksDB included in zig-rocksdb
        .link_vendor = false,
    });

    // Link system libs for RocksDB
    exe.root_module.addImport("rocksdb", dep_rocksdb.module("rocksdb"));
    exe.linkLibrary(dep_rocksdb.artifact("rocksdb"));
    exe.linkSystemLibrary("pthread");
    exe.linkSystemLibrary("stdc++");
    exe.linkSystemLibrary("z"); // compression
    exe.linkSystemLibrary("bz2"); // bzip2 compression
    exe.linkSystemLibrary("lz4"); // lz4 compression
    exe.linkSystemLibrary("snappy"); // snappy compression
    exe.linkSystemLibrary("zstd"); // zstd compression

    const run_cmd = b.addRunArtifact(exe);
    if (b.args) |args| run_cmd.addArgs(args);

    b.installArtifact(exe);

    const run_step = b.step("run", "Run RocksDB benchmark");
    run_step.dependOn(&run_cmd.step);
}
