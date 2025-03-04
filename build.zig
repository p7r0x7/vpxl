// SPDX-License-Identifier: MPL-2.0
// Copyright © 2024 The VPXL Contributors. All rights reserved.
// Contributors responsible for this file:
// @p7r0x7 <mattrbonnette@pm.me>

const std = @import("std");
const Build = @import("std").Build;
const builtin = @import("std").builtin;
const Builddef = @import("builddef").Builddef;

pub fn build(b: *Build) void {
    // Environment defaults
    var def = Builddef.init(b);
    const target, const optimize = def.stdOptions(.{}, .{});

    const vpxl = def.executable("vpxl", "src/main.zig", target, optimize);
    b.installArtifact(vpxl);

    // Dependencies
    const cova = b.dependency("cova", .{ .target = target, .optimize = optimize });
    vpxl.root_module.addImport("cova", cova.module("cova"));

    // Enable `zig build run`
    const run_cmd = def.runArtifact(vpxl, b.args);
    b.step("run", "").dependOn(&run_cmd.step);

    // Enable `zig build test`
    const unit_tests = def.@"test"("src/main.zig", target, optimize);
    const run_unit_tests = def.runArtifact(unit_tests, null);
    b.step("test", "").dependOn(&run_unit_tests.step);
}
