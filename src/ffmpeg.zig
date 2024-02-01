// SPDX-License-Identifier: MPL-2.0
// Copyright © 2023 The VPXL Contributors. All rights reserved.
// Contributors responsible for this file:
// @p7r0x7 <mattrbonnette@pm.me>

const std = @import("std");
const proc = @import("std").process;
const mem = @import("std").mem;

// plan is a structure that stores the configuration state of the locally found-in-path or cli-provided ffmpeg;
// this state can absolutely be cached for better startup performance of vpxl.

pub fn queryFFMPEG(ally: mem.Allocator) !void {
    const d = proc.Child;
    _ = d;
    std.fs.path
        d.init([_][]const u8{"ffmpeg"}, ally);
}
