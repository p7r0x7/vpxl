// SPDX-License-Identifier: MPL-2.0
// Copyright © 2024 The VPXL Contributors. All rights reserved.
// Contributors responsible for this file:
// @p7r0x7 <mattrbonnette@pm.me>

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    b.enable_wine = target.result.os.tag == .windows and target.result.cpu.arch == .x86_64;
    b.enable_rosetta = target.result.os.tag == .macos and target.result.cpu.arch == .x86_64;

    // Build configuration
    const exe = b.addExecutable(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .omit_frame_pointer = optimize != .Debug,
        .unwind_tables = optimize == .Debug,
        .strip = optimize != .Debug,
        .optimize = optimize,
        .target = target,
        .name = "vpxl",
        .pic = true,
    });
    {
        // Dependencies
        const cova = b.dependency("cova", .{ .target = target, .optimize = optimize });
        exe.root_module.addImport("cova", cova.module("cova"));
    }
    exe.want_lto = !target.result.isDarwin(); // https://github.com/ziglang/zig/issues/8680
    exe.compress_debug_sections = .zstd;
    exe.link_function_sections = true;
    exe.link_gc_sections = true;
    b.installArtifact(exe);

    {
        // Enable `zig build run`
        const run_cmd = b.addRunArtifact(exe);
        run_cmd.step.dependOn(b.getInstallStep());
        if (b.args) |args| run_cmd.addArgs(args);
        b.step("run", "").dependOn(&run_cmd.step);
    }
    {
        // Enable `zig build test`
        const unit_tests = b.addTest(.{
            .root_source_file = .{ .path = "src/main.zig" },
            .optimize = optimize,
            .target = target,
        });
        const run_unit_tests = b.addRunArtifact(unit_tests);
        b.step("test", "").dependOn(&run_unit_tests.step);
    }
}
