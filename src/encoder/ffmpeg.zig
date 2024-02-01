const std = @import("std");
const proc = @import("std").process;

pub fn queryFFMPEG() !void {
    var d = proc.Child;
    d.init(argv: []const []const u8, allocator: mem.Allocator)
    _ = d;
}   