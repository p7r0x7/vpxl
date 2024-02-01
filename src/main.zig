// SPDX-License-Identifier: MPL-2.0
// Copyright © 2023 The VPXL Contributors. All rights reserved.
// Contributors responsible for this file:
// @p7r0x7 <mattrbonnette@pm.me>

const io = @import("std").io;
const cli = @import("cli.zig");
const heap = @import("std").heap;

pub fn main() !void {
    // Connect to stderr and write opening and closing newlines.
    const stderr = io.getStdErr();
    const wr = stderr.writer();
    try wr.writeByte(cli.nb);
    defer wr.writeByte(cli.nb) catch unreachable;

    // Run VPXL's CLI using an arena-wrapped stack allocator.
    var buffer: [11 << 10]u8 = undefined;
    var fba = heap.FixedBufferAllocator.init(buffer[0..]);
    var arena = heap.ArenaAllocator.init(fba.allocator());
    try cli.runVPXL(stderr, arena.allocator());
    arena.deinit();
    fba.reset();
}
