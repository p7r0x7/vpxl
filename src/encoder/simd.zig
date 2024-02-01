// SPDX-License-Identifier: MPL-2.0
// Copyright © 2023 The VPXL Contributors. All rights reserved.
// Contributors responsible for this file:
// @notcancername <notcancername@protonmail.com>
// @p7r0x7 <mattrbonnette@pm.me>

const std = @import("std");
const assert = std.debug.assert;

const root = @import("root");
const error_if_non_native = if (@hasDecl(root, "simd_error_if_non_native")) root.simd_error_if_non_native else false;

// zig fmt: off
pub const U8x8   = @Vector(8,   u8); //  64 bits
pub const U8x16  = @Vector(16,  u8); // 128 bits
pub const U8x32  = @Vector(32,  u8); // 256 bits
pub const U8x64  = @Vector(64,  u8); // 512 bits
pub const U16x4  = @Vector(4,  u16); //  64 bits
pub const U16x8  = @Vector(8,  u16); // 128 bits
pub const U16x16 = @Vector(16, u16); // 256 bits
pub const U16x32 = @Vector(32, u16); // 512 bits
pub const I16x4  = @Vector(4,  i16); //  64 bits
pub const I16x8  = @Vector(8,  i16); // 128 bits
pub const I16x16 = @Vector(16, i16); // 256 bits
pub const I16x32 = @Vector(32, i16); // 512 bits
pub const I32x2  = @Vector(2,  i32); //  64 bits
pub const I32x4  = @Vector(4,  i32); // 128 bits
pub const I32x8  = @Vector(8,  i32); // 256 bits
pub const I32x16 = @Vector(16, i32); // 512 bits
// zig fmt: on

// TODO(@notcancername): I really don't think *both* signed and unknowned-signed versions of this are needed.
pub fn WideInt(comptime T: type) type {
    return std.meta.Int(@typeInfo(T).Int.signedness, @bitSizeOf(T) * 2);
}

pub fn WideIntS(comptime T: type, comptime s: std.builtin.Signedness) type {
    return std.meta.Int(s, @bitSizeOf(T) * 2);
}

pub fn WideIntVec(comptime T: type) type {
    const C = @typeInfo(T).Vector.child;
    const l = @typeInfo(T).Vector.len;

    return @Vector(@divExact(l, 2), WideInt(C));
}

pub fn WideVec(comptime T: type) type {
    const C = @typeInfo(T).Vector.child;
    const l = @typeInfo(T).Vector.len;

    return @Vector(l, WideInt(C));
}

pub fn WideVecS(comptime T: type, comptime s: std.builtin.Signedness) type {
    const C = @typeInfo(T).Vector.child;
    const l = @typeInfo(T).Vector.len;

    return @Vector(l, WideIntS(C, s));
}

pub fn WideIntVecS(comptime T: type, comptime s: std.builtin.Signedness) type {
    const C = @typeInfo(T).Vector.child;
    const l = @typeInfo(T).Vector.len;

    return @Vector(@divExact(l, 2), WideIntS(C, s));
}

// TODO(@notcancername): Fix this for RISCV.
pub inline fn truncateVecRetarded(comptime D: type, comptime start: comptime_int, v: anytype) D {
    const d = @typeInfo(D).Vector;
    const mask: [d.len]i32 = comptime generate_mask: {
        var tmp: [d.len]i32 = undefined;
        for (0..d.len, start..) |j, i| tmp[j] = i;
        break :generate_mask tmp;
    };

    return @shuffle(d.child, v, undefined, mask);
}

const truncateVec = truncateVecRetarded;

pub const cur_cpu = @import("builtin").cpu;
pub const cur_features = Features.get(cur_cpu);

pub const Features = struct {
    // TODO(@notcancername): All vector sets in std.Target.x86, std.Target.aarch64, and
    // std.Target.riscv should be listed here, even if they are unused.
    have_mmx: bool = false,
    have_sse: bool = false,
    have_sse2: bool = false,
    have_ssse3: bool = false,
    have_avx: bool = false,
    have_avx2: bool = false,
    have_avx512vl: bool = false,
    have_avx512dq: bool = false,
    have_avx512bw: bool = false,
    have_avx512f: bool = false,

    have_neon: bool = false,
    have_neon_fp: bool = false,
    have_neon_fp_movs: bool = false,

    have_rvv_1p0: bool = false,
    have_rvv_32: bool = false,
    have_rvv_64: bool = false,
    have_rvv_128: bool = false,
    have_rvv_256: bool = false,
    have_rvv_512: bool = false,

    have_hard_f32: bool = false,
    have_hard_f64: bool = false,
    have_hard_mul: bool = false,

    pub fn get(cpu: std.Target.Cpu) Features {
        // zig fmt: off
        return if (cpu.arch.isX86()) .{
            .have_mmx      = std.Target.x86.featureSetHas(cpu.features, .mmx),
            .have_sse      = std.Target.x86.featureSetHas(cpu.features, .sse),
            .have_sse2     = std.Target.x86.featureSetHas(cpu.features, .sse2),
            .have_ssse3    = std.Target.x86.featureSetHas(cpu.features, .ssse3),
            .have_avx      = std.Target.x86.featureSetHas(cpu.features, .avx),
            .have_avx2     = std.Target.x86.featureSetHas(cpu.features, .avx2),
            .have_avx512vl = std.Target.x86.featureSetHas(cpu.features, .avx512vl),
            .have_avx512dq = std.Target.x86.featureSetHas(cpu.features, .avx512dq),
            .have_avx512bw = std.Target.x86.featureSetHas(cpu.features, .avx512bw),
            .have_avx512f  = std.Target.x86.featureSetHas(cpu.features, .avx512f),
            .have_hard_mul = true,
        } else if (cpu.arch.isArmOrThumb()) .{
            .have_neon         = std.Target.arm.featureSetHas(cpu.features, .neon),
            .have_neon_fp      = std.Target.arm.featureSetHas(cpu.features, .neonfp),
            .have_neon_fp_movs = std.Target.arm.featureSetHas(cpu.features, .neon_fpmovs),
            .have_hard_mul     = std.Target.arm.featureSetHas(cpu.features, .mul),
        } else if (cpu.arch.isRISCV()) .{
            .have_rvv_32   = std.Target.riscv.featureSetHas(cpu.features, .zvl32b),
            .have_rvv_64   = std.Target.riscv.featureSetHas(cpu.features, .zvl64b),
            .have_rvv_128  = std.Target.riscv.featureSetHas(cpu.features, .zvl128b),
            .have_rvv_256  = std.Target.riscv.featureSetHas(cpu.features, .zvl256b),
            .have_rvv_512  = std.Target.riscv.featureSetHas(cpu.features, .zvl512b),
            .have_hard_f32 = std.Target.riscv.featureSetHas(cpu.features, .f),
            .have_hard_f64 = std.Target.riscv.featureSetHas(cpu.features, .d),
            .have_hard_mul = std.Target.riscv.featureSetHas(cpu.features, .m),
        };
        // zig fmt: on
    }

    pub fn supportsVectorBits(f: Features, bits: usize) bool {
        return switch (bits) {
            8 => true,
            16 => true,
            32 => f.have_rvv_32,
            64 => f.have_mmx or f.have_rvv_64,
            128 => f.have_sse2 or f.have_rvv_128,
            256 => f.have_avx2 or f.have_rvv_256,
            512 => f.have_avx512vl or f.have_avx512dq or f.have_rvv_512,
            else => false,
        };
    }

    pub fn supportsVectorType(f: Features, comptime T: type) bool {
        return supportsVectorBits(@bitSizeOf(T)) and switch (@typeInfo(T).Vector.child) {
            u16, i16, u32, i32, u64, i64 => f.have_mmx or f.have_avx or f.have_avx2,
            bool => true,
            else => false,
        };
    }
};

inline fn interleave(comptime T: type, a: T, b: T) struct { T, T } {
    const ti = @typeInfo(T).Vector;
    const shuf = comptime b: {
        var tmp: [ti.len * 2]i32 = undefined;
        for (0..ti.len) |e| {
            tmp[e * 2], tmp[e * 2 + 1] = .{ @as(i32, e), ~@as(i32, e) };
        }
        break :b tmp;
    };

    return .{
        @shuffle(ti.child, a, b, shuf[0..ti.len].*),
        @shuffle(ti.child, a, b, shuf[ti.len..].*),
    };
}

inline fn haddGenericSlow(comptime T: type, lhs: T, rhs: T) T {
    if (error_if_non_native) @compileError("non-native operation: hadd(" ++ @typeName(T) ++ ", ...)");

    const x, const y = interleave(T, lhs, rhs);
    return x +% y;
}

inline fn haddsGenericSlow(comptime T: type, lhs: T, rhs: T) void {
    if (error_if_non_native) @compileError("non-native operation: hadds(" ++ @typeName(T) ++ ", ...)");

    const x, const y = interleave(T, lhs, rhs);
    return x +| y;
}

inline fn hsubsGenericSlow(comptime T: type, lhs: T, rhs: T) void {
    if (error_if_non_native) @compileError("non-native operation: hsubs(" ++ @typeName(T) ++ ", ...)");

    const x, const y = interleave(T, lhs, rhs);
    return x -| y;
}

inline fn maddGenericSlow(comptime T: type, lhs: T, rhs: T) WideIntVec(T) {
    if (error_if_non_native) @compileError("non-native operation: madd(" ++ @typeName(T) ++ ", ...)");

    const W = WideIntVec(T);
    const WW = WideVec(T);
    const ti = @typeInfo(T).Vector;

    const low = truncateVec(W, 0, @as(WW, lhs)) * truncateVec(W, 0, @as(WW, rhs));
    const high = truncateVec(W, @divExact(ti.len, 2), @as(WW, lhs)) * truncateVec(W, @divExact(ti.len, 2), @as(WW, rhs));
    return hadd(W, low, high);
}

inline fn sadGenericSlow(comptime T: type, lhs: T, rhs: T) WideIntVecS(T, .signed) {
    if (error_if_non_native) @compileError("non-native operation: sad(" ++ @typeName(T) ++ ", ...)");

    const len = @typeInfo(T).Vector.len;

    const W = WideIntVecS(T, .signed);
    const WW = WideVecS(T, .signed);

    const low = truncateVec(W, 0, @as(WW, lhs)) - truncateVec(W, 0, @as(WW, rhs));
    const high = truncateVec(W, @divExact(len, 2), @as(WW, lhs)) - truncateVec(W, @divExact(len, 2), @as(WW, rhs));

    const red_s1 = hadd(W, low, high);
    const red_s2 = hadd(W, red_s1, @splat(0));
    return hadd(W, red_s2, @splat(0));
}

pub inline fn sad(comptime T: type, lhs: T, rhs: T) T {
    return sadGenericSlow(T, lhs, rhs);
}

pub inline fn hadd(comptime T: type, lhs: T, rhs: T) T {
    return switch (T) {
        I16x4 => hadd_i16x4(lhs, rhs),
        I16x8 => hadd_i16x8(lhs, rhs),
        I16x16 => hadd_i16x16(lhs, rhs),
        else => haddGenericSlow(T, lhs, rhs),
    };
}

pub inline fn hadds(comptime T: type, lhs: T, rhs: T) T {
    return switch (T) {
        I16x4 => hadds_i16x4(lhs, rhs),
        I16x8 => hadds_i16x8(lhs, rhs),
        I16x16 => hadds_i16x16(lhs, rhs),
        else => haddsGenericSlow(T, lhs, rhs),
    };
}

pub inline fn madd(comptime T: type, lhs: T, rhs: T) T {
    return switch (T) {
        I16x4 => madd_i16x4(lhs, rhs),
        I16x8 => madd_i16x8(lhs, rhs),
        I16x16 => madd_i16x16(lhs, rhs),
        I16x32 => madd_i16x32(lhs, rhs),
        else => maddGenericSlow(T, lhs, rhs),
    };
}

pub inline fn reduceGenericHoriz(comptime T: type, comptime horiz: anytype, v: T) @typeInfo(T).Vector.child {
    var tmp = v;
    const nb_of_horiz = comptime std.math.log2_int(usize, @divExact(@typeInfo(T).Vector.len, 2));
    inline for (0..nb_of_horiz) |_| tmp = horiz(T, v, @splat(0));
    return tmp[0]; // the lowest element now contains the reduced value
}

pub inline fn reduceAdd(comptime T: type, v: T) @typeInfo(T).Vector.child {
    // TODO(@notcancername): optimize for applicable architectures
    return reduceGenericHoriz(T, hadd, v);
}

pub inline fn reduceAddSat(comptime T: type, v: T) @typeInfo(T).Vector.child {
    // TODO(@notcancername): optimize for applicable architectures
    return reduceGenericHoriz(T, hadds, v);
}

const Overflow = enum { ub, wrap, sat };

// asm wrappers start here

pub const have_sad_u8x8 = cur_features.have_sse;
pub const have_sad_u8x16 = cur_features.have_avx or cur_features.have_sse2;
pub const have_sad_u8x32 = cur_features.have_avx2;
pub const have_sad_u8x64 = cur_features.have_avx512bw and cur_features.have_avx512vl;

pub const have_hadds_i16x4 = cur_features.have_ssse3;
pub const have_hadds_i16x8 = cur_features.have_ssse3 or cur_features.have_avx;
pub const have_hadds_i16x16 = cur_features.have_avx2;

pub const have_hadd_i16x4 = cur_features.have_ssse3;
pub const have_hadd_i16x8 = cur_features.have_ssse3 or cur_features.have_avx;
pub const have_hadd_i16x16 = cur_features.have_avx2;

pub const have_hsubs_i16x4 = cur_features.have_ssse3;
pub const have_hsubs_i16x8 = cur_features.have_ssse3 or cur_features.have_avx;
pub const have_hsubs_i16x16 = cur_features.have_avx2;

pub const have_madd_i16x4 = cur_features.have_mmx;
pub const have_madd_i16x8 = cur_features.have_sse2 or cur_features.have_avx;
pub const have_madd_i16x16 = cur_features.have_avx2;
pub const have_madd_i16x32 = cur_features.have_avx512bw;

pub inline fn madd_i16x4(lhs: I16x4, rhs: I16x4) I32x2 {
    if (!have_madd_i16x4) return maddGenericSlow(I16x4, lhs, rhs);

    return asm volatile ("pmaddwd %[in], %[out]"
        : [out] "=y" (-> I32x2),
        : [_] "0" (lhs),
          [in] "y" (rhs),
    );
}

pub inline fn madd_i16x8(lhs: I16x8, rhs: I16x8) I32x4 {
    if (!have_madd_i16x8) return maddGenericSlow(I16x8, lhs, rhs);

    if (comptime cur_features.have_avx) {
        return asm volatile ("vpmaddwd %[rhs], %[lhs], %[out]"
            : [out] "=x" (-> I32x4),
            : [lhs] "x" (lhs),
              [rhs] "x" (rhs),
        );
    }
    return asm volatile ("pmaddwd %[in], %[out]"
        : [out] "=x" (-> I32x4),
        : [_] "0" (lhs),
          [in] "x" (rhs),
    );
}

pub inline fn madd_i16x16(lhs: I16x16, rhs: I16x16) I32x8 {
    if (!have_madd_i16x16) return maddGenericSlow(I16x16, lhs, rhs);

    return asm volatile ("vpmaddwd %[rhs], %[lhs], %[out]"
        : [out] "=x" (-> I32x8),
        : [lhs] "x" (lhs),
          [rhs] "x" (rhs),
    );
}

pub inline fn madd_i16x32(lhs: I16x32, rhs: I16x32) I32x16 {
    if (!have_madd_i16x32) return maddGenericSlow(I16x32, lhs, rhs);

    return asm volatile ("vpmaddwd %[rhs], %[lhs], %[out]"
        : [out] "=x" (-> I32x16),
        : [lhs] "x" (lhs),
          [rhs] "x" (rhs),
    );
}

pub inline fn sad_u8x8(lhs: U8x8, rhs: U8x8) U16x4 {
    if (!have_sad_u8x8) return sadGenericSlow(U8x8, lhs, rhs);

    return asm volatile ("psadbw %[in], %[out]"
        : [out] "=y" (-> U16x4),
        : [_] "0" (lhs),
          [in] "y" (rhs),
    );
}

pub inline fn sad_u8x16(lhs: U8x16, rhs: U8x16) U16x8 {
    if (!have_sad_u8x16) return sadGenericSlow(U8x16, lhs, rhs);

    if (comptime cur_features.have_avx) {
        return asm volatile ("vpsadbw %[rhs], %[lhs], %[out]"
            : [out] "=x" (-> U16x8),
            : [lhs] "x" (lhs),
              [rhs] "x" (rhs),
        );
    }
    return asm volatile ("psadbw %[in], %[out]"
        : [out] "=x" (-> U16x8),
        : [_] "0" (lhs),
          [in] "x" (rhs),
    );
}

pub inline fn sad_u8x32(lhs: U8x32, rhs: U8x32) U16x16 {
    if (!have_sad_u8x32) return sadGenericSlow(U8x32, lhs, rhs);

    return asm volatile ("vpsadbw %[rhs], %[lhs], %[out]"
        : [out] "=x" (-> U16x16),
        : [lhs] "x" (lhs),
          [rhs] "x" (rhs),
    );
}

pub inline fn sad_u8x64(lhs: U8x64, rhs: U8x64) U16x32 {
    if (!have_sad_u8x64) return sadGenericSlow(U8x64, lhs, rhs);

    return asm volatile ("vpsadbw %[rhs], %[lhs], %[out]"
        : [out] "=x" (-> U16x32),
        : [lhs] "x" (lhs),
          [rhs] "x" (rhs),
    );
}

pub inline fn hadds_i16x4(lhs: I16x4, rhs: I16x4) I16x4 {
    if (!have_hadds_i16x4) return haddsGenericSlow(I16x4, lhs, rhs);
    return asm volatile ("phaddsw %[in], %[out]"
        : [out] "=y" (-> I16x4),
        : [_] "0" (lhs),
          [in] "y" (rhs),
    );
}

pub inline fn hadds_i16x8(lhs: I16x8, rhs: I16x8) I16x8 {
    if (!have_hadds_i16x8) return haddsGenericSlow(I16x8, lhs, rhs);
    if (comptime cur_features.have_avx) {
        return asm volatile ("vphaddsw %[b], %[a], %[out]"
            : [out] "=x" (-> I16x8),
            : [a] "x" (lhs),
              [b] "x" (rhs),
        );
    }
    asm volatile ("phaddsw %[in], %[out]"
        : [out] "=x" (-> I16x8),
        : [_] "0" (lhs),
          [in] "x" (rhs),
    );
}

pub inline fn hadds_i16x16(lhs: I16x16, rhs: I16x16) I16x16 {
    if (!have_hadds_i16x16) return haddsGenericSlow(I16x16, lhs, rhs);
    return asm volatile ("vphaddsw %[b], %[a], %[out]"
        : [out] "=x" (-> I16x16),
        : [a] "x" (lhs),
          [b] "x" (rhs),
    );
}

pub inline fn hadd_i16x4(lhs: I16x4, rhs: I16x4) I16x4 {
    if (!have_hadd_i16x4) return haddGenericSlow(I16x4, lhs, rhs);
    return asm volatile ("phaddw %[in], %[out]"
        : [out] "=y" (-> I16x4),
        : [_] "0" (lhs),
          [in] "y" (rhs),
    );
}

pub inline fn hadd_i16x8(lhs: I16x8, rhs: I16x8) I16x8 {
    if (!have_hadd_i16x8) return haddGenericSlow(I16x8, lhs, rhs);
    if (comptime cur_features.have_avx) {
        return asm volatile ("vphaddw %[b], %[a], %[out]"
            : [out] "=x" (-> I16x8),
            : [a] "x" (lhs),
              [b] "x" (rhs),
        );
    }
    asm volatile ("phaddw %[in], %[out]"
        : [out] "=x" (-> I16x8),
        : [_] "0" (lhs),
          [in] "x" (rhs),
    );
}

pub inline fn hadd_i16x16(lhs: I16x16, rhs: I16x16) I16x16 {
    if (!have_hadd_i16x16) return haddGenericSlow(I16x16, lhs, rhs);
    return asm volatile ("vphaddw %[b], %[a], %[out]"
        : [out] "=x" (-> I16x16),
        : [a] "x" (lhs),
          [b] "x" (rhs),
    );
}

pub inline fn hsubs_i16x4(lhs: I16x4, rhs: I16x4) I16x4 {
    if (!have_hsubs_i16x4) return hsubsGenericSlow(I16x4, lhs, rhs);
    return asm volatile ("phsubsw %[in], %[out]"
        : [out] "=y" (-> I16x4),
        : [_] "0" (lhs),
          [in] "y" (rhs),
    );
}

pub inline fn hsubs_i16x8(lhs: I16x8, rhs: I16x8) I16x8 {
    if (!have_hsubs_i16x8) return hsubsGenericSlow(I16x8, lhs, rhs);
    if (comptime cur_features.have_avx) {
        return asm volatile ("vphsubsw %[b], %[a], %[out]"
            : [out] "=x" (-> I16x8),
            : [a] "x" (lhs),
              [b] "x" (rhs),
        );
    }
    asm volatile ("phsubsw %[in], %[out]"
        : [out] "=x" (-> I16x8),
        : [_] "0" (lhs),
          [in] "x" (rhs),
    );
}

pub inline fn hsubs_i16x16(lhs: I16x16, rhs: I16x16) I16x16 {
    if (!have_hsubs_i16x16) return hsubsGenericSlow(I16x16, lhs, rhs);
    return asm volatile ("vphsubsw %[b], %[a], %[out]"
        : [out] "=x" (-> I16x16),
        : [a] "x" (lhs),
          [b] "x" (rhs),
    );
}

// Local Variables:
// rmsbolt-command: "zig build-exe -O ReleaseFast -target riscv64-freestanding -mcpu generic_rv64+m+a+f+v+c+d"
// End:
