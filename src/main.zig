const io = @import("std").io;
const cli = @import("cli.zig");
const heap = @import("std").heap;

pub fn main() !void {
    // Connect to pipes & run VPXL's CLI using an arena-wrapped stack allocator
    const stderr = io.getStdErr().writer();
    var bw = io.bufferedWriter(stderr);
    var buffer: [384 << 10]u8 = undefined;
    var fba = heap.FixedBufferAllocator.init(buffer[0..]);
    var arena = heap.ArenaAllocator.init(fba.allocator());
    try cli.runVPXL(&bw, arena.allocator());
    arena.deinit();
}
