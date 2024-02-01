const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const exe = b.addExecutable(.{
        .name = "vpxl",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    // Dependencies
    const cova = b.dependency("cova", .{ .target = target, .optimize = optimize });
    exe.addModule("cova", cova.module("cova"));

    exe.link_gc_sections = optimize != .Debug;
    exe.want_lto = !target.isDarwin(); // https://github.com/ziglang/zig/issues/8680
    exe.strip = optimize != .Debug;
    b.installArtifact(exe);

    // Enable `zig build run`
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    b.step("run", "").dependOn(&run_cmd.step);

    // Enable `zig build test`
    const unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    const run_unit_tests = b.addRunArtifact(unit_tests);
    b.step("test", "").dependOn(&run_unit_tests.step);
}
