// SPDX-License-Identifier: MPL-2.0
// Copyright © 2024 The VPXL Contributors. All rights reserved.
// Contributors responsible for this file:
// @p7r0x7 <mattrbonnette@pm.me>

const std = @import("std");
const Build = @import("std").Build;
const builtin = @import("std").builtin;

pub fn build(b: *Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    b.enable_wine = target.result.os.tag == .windows and target.result.cpu.arch == .x86_64;
    b.enable_rosetta = target.result.os.tag == .macos and target.result.cpu.arch == .x86_64;

    const vpxl = executable(b, "vpxl", "src/main.zig", target, optimize);
    b.installArtifact(vpxl);
    {
        // Dependencies
        const cova = b.dependency("cova", .{ .target = target, .optimize = optimize });
        vpxl.root_module.addImport("cova", cova.module("cova"));
    }
    {
        // Enable `zig build run`
        const run_cmd = b.addRunArtifact(vpxl);
        run_cmd.step.dependOn(b.getInstallStep());
        if (b.args) |args| run_cmd.addArgs(args);
        b.step("run", "").dependOn(&run_cmd.step);
    }
    {
        // Enable `zig build test`
        const unit_tests = b.addTest(.{
            .root_source_file = b.path("src/main.zig"),
            .optimize = optimize,
            .target = target,
        });
        const run_unit_tests = b.addRunArtifact(unit_tests);
        b.step("test", "").dependOn(&run_unit_tests.step);
    }
}

fn executable(b: *Build, name: []const u8, root_path: []const u8, target: Build.ResolvedTarget, optimize: builtin.OptimizeMode) *Build.Step.Compile {
    const exe = b.addExecutable(.{
        .error_tracing = optimize == .ReleaseSafe or optimize == .Debug,
        .strip = optimize == .ReleaseFast or optimize == .ReleaseSmall,
        .omit_frame_pointer = optimize != .Debug,
        .root_source_file = b.path(root_path),
        .unwind_tables = optimize == .Debug,
        .optimize = optimize,
        .target = target,
        .name = name,
        .pic = true,
    });
    exe.want_lto = !target.result.isDarwin(); // https://github.com/ziglang/zig/issues/8680
    exe.compress_debug_sections = .zstd;
    exe.link_function_sections = true;
    exe.link_gc_sections = true;
    return exe;
}
