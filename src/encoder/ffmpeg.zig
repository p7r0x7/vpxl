const std = @import("std");
const proc = @import("std").process;
const mem = @import("std").mem;

pub fn queryFFMPEG(ally: mem.Allocator) !void {
    const d = proc.Child;
    _ = d;
    std.fs.path
        .d.init([_][]const u8{"ffmpeg"}, ally);
}
