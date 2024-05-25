// SPDX-License-Identifier: MPL-2.0
// Copyright © 2024 The VPXL Contributors. All rights reserved.
// Contributors responsible for this file:
// @notcancername <notcancername@protonmail.com>

const std = @import("std");
const assert = std.debug.assert;

fn FastInt(comptime T: type) type {
    return std.meta.Int(@typeInfo(T).Int.signedness, @sizeOf(T));
}

// TODO: OPTIMIZE.

pub const NutReader = struct {
    bit_reader: std.io.BitReader(.big, std.io.AnyReader),

    /// Initializes a `NutReader` with the given `AnyReader`.
    pub fn init(reader: std.io.AnyReader) NutReader {
        return .{
            .bit_reader = std.io.bitReader(.big, reader),
        };
    }

    /// Errors that may occur while reading.
    pub const ReadError = std.io.AnyReader.Error;

    /// Reads `bits` bits of type `T` from `nr`. If an error is returned, the stream is in
    /// an unspecified state.
    pub fn readFixed(nr: *NutReader, comptime T: type, bits: FastInt(std.math.Log2IntCeil(T))) ReadError!T {
        assert(bits <= std.math.maxInt(std.math.Log2IntCeil(T)));
        return nr.bit_reader.readBitsNoEof(T, bits);
    }

    /// Reads a `bits`-bit integer of type `T` from `nr`. If an error is returned, the stream is in
    /// an unspecified state.
    pub fn readUnsigned(nr: *NutReader, comptime T: type, bits: FastInt(std.math.Log2IntCeil(T))) ReadError!T {
        assert(bits <= std.math.maxInt(std.math.Log2IntCeil(T)));
        return nr.bit_reader.readBitsNoEof(T, bits);
    }

    /// Errors that may occur while reading integers.
    const ReadIntError = error{Overflow} || ReadError;

    /// Reads a variable-length integer of type `T` from `nr`. If an error is returned, the stream
    /// is in an unspecified state.
    pub fn readVariable(
        nr: *NutReader,
        comptime T: type,
    ) ReadIntError!T {
        const UT = std.meta.Int(.unsigned, @bitSizeOf(T));
        var leb = try std.leb.readULEB128(UT, nr.bit_reader.reader());

        if (@typeInfo(T).Int.signedness == .signed) {
            leb +%= 1;
            // zigzag encoding: even numbers are positive, odd ones negative.
            return if (leb % 2 == 0) @intCast(leb / 2) else -@as(T, @intCast(leb / 2));
        }

        return leb;
    }

    /// Errors that may occur when reading slices.
    const ReadSliceError = error{TooLong} || ReadIntError;

    /// Reads a variable-length byte slice of up to `max` bytes from `nr`. The byte slice may
    /// contain null bytes. If `error.TooLong` is returned, the stream is in a valid state, but the
    /// slice is lost. If any other error is returned, the stream is in an unspecified state.
    pub fn readSlice(
        nr: *NutReader,
        comptime T: type,
        allocator: std.mem.Allocator,
        max: usize,
    ) ReadSliceError![]T {
        const len = try nr.readVariable(usize);
        const size = if (std.meta.hasUniqueRepresentation(T)) @sizeOf(T) else null;
        const reader = nr.bit_reader.reader();
        if (len > max) {
            if (size) |sz| {
                try reader.skipBytes(@intCast(len * sz), .{});
            } else {}
            return error.TooLong;
        }
        const slice = try allocator.alloc(T, len);
        errdefer allocator.free(slice);
        try reader.readAll(slice);
        return slice;
    }

    /// Errors that may occur when reading slices.
    const ReadStringError = error{ NullByte, InvalidUtf8 } || ReadSliceError;

    /// Reads a variable-length string of up to `max` bytes from `nr`. If `verify_utf8` is false, do
    /// not verify that the string is valid UTF-8. The string must not contain null bytes. If
    /// `error.TooLong`, `error.InvalidUtf8`, or `error.NullByte` is returned, the stream is in a
    /// valid state, but the slice is lost. If any other error is returned, the stream is in an
    /// unspecified state.
    pub fn readString(
        nr: *NutReader,
        allocator: std.mem.Allocator,
        max: usize,
        verify_utf8: bool,
    ) ReadStringError![]u8 {
        const slice = try nr.readSlice(u8, allocator, max);
        if (std.mem.indexOfScalar(u8, slice, 0)) |_| return error.NullByte;
        if (verify_utf8 and !std.unicode.utf8ValidateSlice(slice)) return error.InvalidUtf8;
        return slice;
    }
};

pub const NutState = struct {
    pub const file_id_string = "nut/multimedia container\x00";

    pub const Startcode = enum(u64) {
        // zig fmt: off
        main      = 0x7A561F5F04AD +% (('N' << 8 +% 'M') << 48),
        stream    = 0x11405BF2F9DB +% (('N' << 8 +% 'S') << 48),
        syncpoint = 0xE4ADEECA4569 +% (('N' << 8 +% 'K') << 48),
        index     = 0xDD672F23E64E +% (('N' << 8 +% 'X') << 48),
        info      = 0xAB68B596BA78 +% (('N' << 8 +% 'I') << 48),
        _,
        // zig fmt: on
    };

    pub const PacketHeader = struct {
        startcode: u64,
        forward_ptr: usize,
        header_checksum: u32,
    };

    pub const PacketFooter = struct {
        checksum: u32,
    };

    pub const Timebase = struct {
        num: u64,
        denom: u64,
    };

    pub const MainHeader = struct {
        version: u8,
        minor_version: u8,
        nb_streams: u8,
        max_distance: u8,
        time_bases: Timebase,
    };

    reader: NutReader,
};
