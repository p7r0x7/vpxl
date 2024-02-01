// SPDX-License-Identifier: MPL-2.0
// Copyright © 2023 The VPXL Contributors. All rights reserved.
// Contributors responsible for this file:
// @p7r0x7 <mattrbonnette@pm.me>

const std = @import("std");
const mem = @import("std").mem;

pub const LowBD = i8;
pub const HighBD = i16;

pub fn PlaneBuffer(comptime Depth: type, ally: mem.Allocator) type {
    if (Depth != LowBD and Depth != HighBD) @compileError("dumbass");

    return struct {
        data: ?[]Depth = null,
        width: u16 = 0,
        height: u16 = 0,
        mut: ?std.Thread.RwLock = null,

        pub fn deinit(f: *@This()) void {
            f.mut.lock();
            if (f.data) |data| ally.free(data);
            f.mut.unlock();
        }
    };
}

pub fn FrameBuffer(comptime Depth: type, width: usize, height: usize, ally: mem.Allocator) type {
    _ = width;
    _ = height;
    _ = ally;
    if (Depth != LowBD and Depth != HighBD) @compileError("dumbass");

    return struct {
        y: ?PlaneBuffer,
        u: ?PlaneBuffer,
        v: ?PlaneBuffer,
        a: ?PlaneBuffer,
        g: ?PlaneBuffer,
        b: ?PlaneBuffer,
        r: ?PlaneBuffer,

        pub fn isRGB(f: *@This()) bool {
            return f.y.data == null;
        }

        pub fn deinit(f: *@This()) void {
            inline for (.{ f.y, f.u, f.v, f.a, f.g, f.b, f.r }) |p| p.deinit();
        }
    };
}
