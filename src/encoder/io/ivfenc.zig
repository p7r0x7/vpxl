const std = @import("std");
const fs = std.fs;
const io = std.io;
const mem = std.mem;

pub const IVFSignature = "DKIF";
pub const IVFHeaderSize = 32;
pub const IVFFrameHeaderSize = 12;

pub const IVFHeader = extern struct {
    signature: [IVFSignature.len]u8, // "DKIF"
    version: u16, // File format version (usually 0)
    header_size: u16, // Size of the header in bytes (32 bytes for version 0)
    fourcc: [4]u8, // Codec used (e.g., "VP80" for VP8, "VP90" for VP9)
    width: u16, // Width of the video in pixels
    height: u16, // Height of the video in pixels
    framerate_num: u32, // The numerator of framerate
    framerate_den: u32, // The denominator of framerate
    num_frames: u32, // Total number of frames in the file
    unused: u32, // Reserved for future use (set to 0)
};

pub const IVFFrameHeader = extern struct {
    frame_size: u32, // Size of the frame data in bytes
    timestamp: u64, // Presentation timestamp of the frame in time units
};

pub const IVFReader = struct {
    header: IVFHeader,
    file: fs.File,
    reader: fs.File.Reader,

    const Self = @This();

    pub fn init(file: fs.File) !IVFReader {
        var self = IVFReader{
            .file = file,
            .reader = file.reader(),
            .header = undefined,
        };
        try self.readIVFHeader();
        return self;
    }

    pub fn deinit(_: *Self) void {}

    fn readIVFHeader(self: *Self) !void {
        var r = self.reader;
        self.header = try r.readStruct(IVFHeader);
        if (!mem.eql(u8, &self.header.signature, IVFSignature)) {
            return error.IvfFormat;
        }
        if (self.header.version != 0) {
            return error.IvfFormat;
        }
        if (self.header.header_size != 32) {
            return error.IvfFormat;
        }
    }

    pub fn readIVFFrameHeader(self: *Self, frame_header: *IVFFrameHeader) !void {
        frame_header.frame_size = try self.reader.readIntLittle(u32);
        frame_header.timestamp = try self.reader.readIntLittle(u64);
    }

    pub fn readFrame(self: *Self, frame: []u8) !usize {
        return try self.file.readAll(frame);
    }

    pub fn skipFrame(self: *Self, frame_size: u32) !void {
        try self.file.seekBy(frame_size);
    }
};

pub const IVFWriter = struct {
    file: fs.File,
    writer: fs.File.Writer,
    frame_count: u32,

    const Self = @This();

    pub fn init(file: fs.File, header: *const IVFHeader) !IVFWriter {
        var self = IVFWriter{
            .file = file,
            .writer = file.writer(),
            .frame_count = 0,
        };
        if (!mem.eql(u8, &header.signature, IVFSignature)) {
            return error.IvfFormat;
        }
        if (header.version != 0) {
            return error.IvfFormat;
        }
        if (header.header_size != 32) {
            return error.IvfFormat;
        }
        // Assuming the host is little endian
        try self.writer.writeAll(@as([*]const u8, @ptrCast(header))[0..@sizeOf(IVFHeader)]);
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.file.seekTo(24) catch {
            // Not seekable. return silently.
            return;
        };
        self.writer.writeIntLittle(u32, self.frame_count) catch {
            return;
        };
        self.file.seekFromEnd(0) catch {
            return;
        };
    }

    pub fn writeIVFFrame(self: *Self, frame: []const u8, timestamp: u64) !void {
        try self.writer.writeIntLittle(u32, @as(u32, @truncate(frame.len)));
        try self.writer.writeIntLittle(u64, timestamp);
        try self.writer.writeAll(frame);
        self.frame_count += 1;
    }
};
