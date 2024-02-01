const std = @import("std");
const fs = @import("std").fs;
const io = @import("std").io;
const mem = @import("std").mem;
const fmt = @import("std").fmt;

pub const signature = "YUV4MPEG2";
pub const frame_header = "FRAME\n";

pub fn Demuxer()


pub const Format = struct { color: Color, location: ChromaLocation, bytesPerFrame: u32 };

pub const ChromaLocation = enum { center, left, topleft, unspecified };

pub const Color = enum {
    C420jpeg,
    C420mpeg2,
    C420paldv,
    C420p16,
    C422p16,
    C444p16,
    C420p14,
    C422p14,
    C444p14,
    C420p12,
    C422p12,
    C444p12,
    C420p10,
    C422p10,
    C444p10,
    C420p9,
    C422p9,
    C444p9,
    C420,
    C411,
    C422,
    C444alpha,
    C444,
    Cmono16,
    Cmono12,
    Cmono10,
    Cmono9,
    Cmono,
    unknown,
};

pub const Y4MHeader = struct {
    width: u16,
    height: u16,
    framerate_num: u32,
    framerate_den: u32,
    color: Color,

    const Self = @This();
    pub fn frameSize(self: *Self) !u32 {
        switch (self.color) {
            Color.i420 => return self.width * self.height * 3 / 2,
            Color.i422 => return self.width * self.height * 2,
            else => return error.Y4MFormat,
        }
    }
    pub fn colorStr(self: *Self) ![]const u8 {
        switch (self.color) {
            Color.i420 => return "420",
            Color.i422 => return "422",
            else => return error.Y4MFormat,
        }
    }
};

pub const Y4MReader = struct {
    header: Y4MHeader,
    file: fs.File,
    frame_size: u32,

    const Self = @This();

    pub fn init(file: fs.File) !Y4MReader {
        var self = Y4MReader{
            .file = file,
            .header = undefined,
            .frame_size = undefined,
        };
        self.header.color = Color.unknown;
        try self.readY4MHeader();
        self.frame_size = try self.header.frameSize();
        return self;
    }

    pub fn deinit(_: *Self) void {}

    fn readY4MHeader(self: *Self) !void {
        var r = self.file.reader();
        var buf: [1024]u8 = undefined;

        // Read until '\n'
        var count: u32 = 0;
        while (true) : (count += 1) {
            if (count >= buf.len) {
                return error.Y4MFormat;
            }
            buf[count] = try r.readByte();
            if (buf[count] == '\n') {
                break;
            }
        }
        if (count == 0) {
            return error.Y4MFormat;
        }

        var it = mem.split(u8, buf[0..count], " ");
        if (it.next()) |v| {
            if (!mem.eql(u8, v, signature)) {
                return error.Y4MFormat;
            }
        }
        while (it.next()) |v| {
            switch (v[0]) {
                'C' => {
                    if (mem.eql(u8, v[1..], "420")) {
                        self.header.color = Color.i420;
                    } else if (mem.eql(u8, v[1..], "422")) {
                        self.header.color = Color.i422;
                    } else {
                        self.header.color = Color.unknown;
                    }
                },
                'W' => self.header.width = try fmt.parseInt(u16, v[1..], 10),
                'H' => self.header.height = try fmt.parseInt(u16, v[1..], 10),
                'F' => {
                    var it2 = mem.split(u8, v[1..], ":");
                    if (it2.next()) |v2| {
                        self.header.framerate_num = try fmt.parseInt(u32, v2, 10);
                    } else {
                        return error.Y4MFormat;
                    }
                    if (it2.next()) |v2| {
                        self.header.framerate_den = try fmt.parseInt(u32, v2, 10);
                    } else {
                        return error.Y4MFormat;
                    }
                },
                'I' => if (!mem.eql(u8, v[1..], "p")) return error.Y4MNotSupported,
                'A' => if (!mem.eql(u8, v[1..], "1:1")) return error.Y4MNotSupported,
                else => continue,
            }
        }
    }

    pub fn readFrame(self: *Self, frame: []u8) !usize {
        var buf: [frame_header.len]u8 = undefined;
        if (frame_header.len != try self.file.readAll(&buf)) {
            return error.EndOfStream;
        }
        if (!mem.eql(u8, &buf, frame_header)) {
            return error.Y4MFormat;
        }
        return try self.file.readAll(frame);
    }

    pub fn skipFrame(self: *Self) !void {
        var buf: [frame_header.len]u8 = undefined;
        if (frame_header.len != try self.file.readAll(&buf)) {
            return error.EndOfStream;
        }
        if (!mem.eql(u8, &buf, frame_header)) {
            return error.Y4MFormat;
        }
        try self.file.seekBy(self.frame_size);
    }
};
