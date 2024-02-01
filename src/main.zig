const io = @import("std").io;
const cli = @import("cli.zig");
const heap = @import("std").heap;

pub fn main() !void {
    // Connect to stderr & run VPXL's CLI using an arena-wrapped stack allocator
    var buffer: [56 << 10]u8 = undefined;
    var fba = heap.FixedBufferAllocator.init(buffer[0..]);
    var arena = heap.ArenaAllocator.init(fba.allocator());
    try cli.runVPXL(io.getStdErr(), arena.allocator());
    arena.deinit();
    fba.reset();
}
