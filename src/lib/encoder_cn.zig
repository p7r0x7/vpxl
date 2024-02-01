// SPDX-License-Identifier: MPL-2.0
// Copyright © 2023 The VPXL Contributors. All rights reserved.
// Contributors responsible for this file:
// @notcancername <notcancername@protonmail.com>

const std = @import("std");
const mem = std.mem;
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const types = @import("types.zig");

pub fn Frame(comptime _Elem: type) type {
    return struct {
        pub const Elem = _Elem;
        data: []Elem,
        subsampling: types.PixelFormat,
        planes: [3]FlatPlane(Elem),
    };
}

/// All samples are sequential within a row. Between rows, there may be additional
/// spacing.
pub fn FlatPlane(comptime _Elem: type) type {
    return struct {
        pub const Elem = _Elem;
        const Plane = @This();

        rows: usize,
        columns: usize,
        row_stride: usize,
        data: [*]Elem,

        pub fn validate(plane: *const Plane) bool {
            return plane.rows >= 1 and plane.columns >= 1 and plane.row_stride >= plane.columns;
        }

        pub fn getLen(plane: *const Plane) usize {
            return plane.row_stride * plane.rows;
        }

        pub fn dataSlice(plane: *const Plane) []Elem {
            return plane.data[0..plane.getLen()];
        }

        pub fn integralImage(plane: *Plane) void {
            assert(plane.validate());

            // TODO: optimize https://github.com/ermig1979/Simd/blob/master/src/Simd/SimdAvx2Integral.cpp
            var row_iter = plane.rowIterator();

            {
                var prev: Elem = 0;
                for (row_iter.next().?[1..]) |*d| {
                    d.* +%= prev;
                    prev = d.*;
                }
            }

            while (row_iter.next()) |row| {
                var prev: Elem = 0;
                for (row[1..]) |*d| {
                    d.* +%= prev;
                    prev = d.*;
                }
            }
        }

        pub fn copyFromExtend(dst: *const Plane, src: *const Plane) !void {
            if (!dst.compatibleWith(src)) return error.IncompatiblePlanes;

            var src_row_iter = src.rowIterator();
            var dst_row_iter = dst.rowIterator();
            while (src_row_iter.next()) |src_row| {
                const dst_row = dst_row_iter.next().?;

                for (dst_row, src_row) |*d, s| {
                    d.* = s;
                }
            }
        }

        pub fn copyFromTruncate(dst: *const Plane, src: *const Plane) !void {
            if (!dst.compatibleWith(src)) return error.IncompatiblePlanes;

            var src_row_iter = src.rowIterator();
            var dst_row_iter = dst.rowIterator();
            while (src_row_iter.next()) |src_row| {
                const dst_row = dst_row_iter.next().?;

                for (dst_row, src_row) |*d, s| {
                    d.* = @truncate(s);
                }
            }
        }

        pub fn copyFrom(dst: *const Plane, src: *const Plane) !void {
            if (!dst.compatibleWith(src)) return error.IncompatiblePlanes;

            var src_row_iter = src.rowIterator();
            var dst_row_iter = dst.rowIterator();

            while (src_row_iter.next()) |src_row| {
                const dst_row = dst_row_iter.next().?;
                @memcpy(dst_row, src_row);
            }
        }

        pub fn copyFromPlanar(
            ally: Allocator,
            rows: usize,
            columns: usize,
            row_stride: usize,
            data: [*]Elem,
        ) Allocator.Error!Plane {
            return .{
                .rows = rows,
                .columns = columns,
                .row_stride = row_stride,
                .data = (try ally.dupe(Elem, data[0 .. rows * row_stride])).ptr,
            };
        }

        pub fn copyFromPacked(
            ally: Allocator,
            rows: usize,
            columns: usize,
            row_stride: usize,
            nb_components: usize,
            data: [*]Elem,
        ) Allocator.Error![]Plane {
            var planes = try ally.alloc(Plane, nb_components);
            {
                var cur_component: usize = 0;
                errdefer for (planes[0..cur_component]) |plane| plane.deinit();

                while (cur_component < nb_components) : (cur_component += 1) {
                    planes[cur_component] = try alloc(ally, rows, columns, row_stride);
                }
            }

            for (0..rows) |row| {
                const row_off = rows * row_stride * nb_components;
                for (0..columns) |column| {
                    const row_col_off = row_off + column * nb_components;
                    for (planes, 0..) |plane, component| {
                        plane.at(row, column).* = data[row_col_off + component];
                    }
                }
            }

            return planes;
        }

        pub fn alloc(ally: Allocator, rows: usize, columns: usize, row_stride: usize) Allocator.Error!Plane {
            return Plane{
                .rows = rows,
                .columns = columns,
                .row_stride = row_stride,
                .data = (try ally.alloc(Elem, rows * row_stride)).ptr,
            };
        }

        pub fn dealloc(plane: Plane, ally: Allocator) void {
            ally.deinit(plane.dataSlice());
        }

        pub fn deinit(plane: *Plane, ally: Allocator) void {
            plane.dealloc(ally);
            plane.* = undefined;
        }

        pub fn compatibleWith(x: Plane, y: Plane) bool {
            return x.rows == y.rows and x.columns == y.columns and x.depth == y.depth;
        }

        pub fn at(plane: Plane, row: usize, col: usize) *Elem {
            return &plane.data[row * plane.row_stride + col];
        }

        pub fn extractFromPacked(plane: *Plane, nb_components: usize, component: usize, data: [*]Elem) void {
            for (0..plane.rows) |row| {
                for (0..plane.columns) |col| {
                    plane.at(row, col).* = data[row * plane.row_stride * nb_components + col * nb_components + component];
                }
            }
        }

        fn rowIterator(plane: *Plane) RowIterator {
            return RowIterator{
                .buf = plane.buf,
                .row_stride = plane.row_stride,
                .columns = plane.columns,
            };
        }

        pub const RowIterator = struct {
            buf: []Elem,
            row_stride: usize,
            columns: usize,

            pos: usize = 0,

            pub const Error = error{OutOfBounds};

            pub fn isAtEnd(iter: *const RowIterator) bool {
                return iter.pos >= iter.buf.len;
            }

            pub fn isAtStart(iter: *const RowIterator) bool {
                return iter.pos == 0;
            }

            pub fn cur(iter: *const RowIterator) []Elem {
                return iter.buf[iter.pos..][0..iter.columns];
            }

            pub fn advance(iter: *RowIterator) Error!void {
                if (iter.isAtEnd()) return error.OutOfBounds;
                iter.pos += iter.row_stride;
            }

            pub fn rewind(iter: *RowIterator) Error!void {
                if (iter.isAtStart()) return error.OutOfBounds;
                iter.pos -= iter.row_stride;
            }

            pub fn next(iter: *RowIterator) ?[]Elem {
                const res = iter.cur();
                iter.advance() catch return null;
                return res;
            }

            pub fn prev(iter: *RowIterator) ?[]Elem {
                iter.rewind() catch return null;
                return iter.cur();
            }

            pub fn set(iter: *RowIterator, row: usize) Error!void {
                const new_pos = row * iter.row_stride;
                if (new_pos >= iter.buf.len) return error.OutOfBounds;
                iter.pos = new_pos;
            }
        };
    };
}
