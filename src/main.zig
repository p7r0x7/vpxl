// SPDX-License-Identifier: MPL-2.0
// Copyright © 2023 The VPXL Contributors. All rights reserved.
// Contributors responsible for this file:
// @p7r0x7 <mattrbonnette@pm.me>

const io = @import("std").io;
const cli = @import("cli.zig");
const heap = @import("std").heap;
const time = @import("std").time;

pub fn main() !void {
    //const start = time.nanoTimestamp();

    // Connect to stderr.
    const stderr = io.getStdErr();

    // Run VPXL's CLI using an arena-wrapped stack allocator.
    var buffer: [14 << 10]u8 = undefined;
    var fba = heap.FixedBufferAllocator.init(buffer[0..]);
    try cli.runVPXL(stderr, fba.allocator());
    fba.reset();
}
