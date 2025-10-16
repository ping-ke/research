const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Create executable
    const exe = b.addExecutable(.{
        .name = "bench_rocksdb",
        .root_module = b.addModule("root", .{
            .root_source_file = b.path("main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Add dependency: copy from jiacai2050/zig-rocksdb
    const dep_rocksdb = b.dependency("rocksdb", .{ .link_vendor = false });
    exe.root_module.addImport("rocksdb", dep_rocksdb.module("rocksdb"));
    exe.linkLibC(); // 需要 C 运行时支持
    exe.linkSystemLibrary("rocksdb"); // 链接系统级 rocksdb 库（C 库）

    const clap = b.dependency("clap", .{});
    exe.root_module.addImport("clap", clap.module("clap"));

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    b.step("run", "Run benchmark").dependOn(&run_cmd.step);
}
