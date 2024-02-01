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
        r: ?PlaneBuffer,
        g: ?PlaneBuffer,
        b: ?PlaneBuffer,
        a: ?PlaneBuffer,

        pub fn isRGB(f: *@This()) bool {
            return f.y.data == null;
        }

        pub fn deinit(f: *@This()) void {
            inline for (.{ f.y, f.u, f.v, f.r, f.g, f.b, f.a }) |p| p.deinit();
        }
    };
}
