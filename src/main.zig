const std = @import("std");
const io = @import("std").io;
const cli = @import("cli.zig");
const mem = @import("std").mem;
const heap = @import("std").heap;
const builtin = @import("builtin");

pub fn main() !void {
    // Heapspace Initialization
    const ally: mem.Allocator = ally: {
        if (builtin.mode == .Debug) {
            var gpa = heap.GeneralPurposeAllocator(.{}){};
            var arena = heap.ArenaAllocator.init(gpa.allocator());
            break :ally arena.allocator();
            // arena of gpa
        } else {
            var arena = heap.ArenaAllocator.init(heap.page_allocator);
            var sfa = heap.stackFallback(4 << 20, arena.allocator());
            break :ally sfa.get();
            // stack then arena of page
        }
    };

    // Connect to pipes & run VPXL's CLI
    var stderr = io.getStdErr().writer();
    var bw = io.bufferedWriter(stderr);
    try cli.runVPXL(&bw, ally);
}
