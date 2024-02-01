const std = @import("std");
const math = @import("std").math;

//typedef struct XPSNRCalculator
//{
//  /* required basic variables */
//  const AVClass   *class;
//  int             bpp; /* unpacked */
//  int             depth; /* packed */
//  char            comps[4];
//  int             numComps;
//  uint64_t        numFrames64;
//  unsigned        frameRate;
//  FFFrameSync     fs;
//  int             lineSizes[4];
//  int             planeHeight[4];
//  int             planeWidth[4];
//  uint8_t         rgbaMap[4];
//  FILE            *statsFile;
//  char            *statsFileStr;
//  /* XPSNR specific variables */
//  double          *sseLuma;
//  double          *weights;
//  AVBufferRef*    bufOrg  [3];
//  AVBufferRef*    bufOrgM1[3];
//  AVBufferRef*    bufOrgM2[3];
//  AVBufferRef*    bufRec  [3];
//  uint64_t        maxError64;
//  double          sumWDist[3];
//  double          sumXPSNR[3];
//  bool            andIsInf[3];
//  bool            isRGB;
//  PSNRDSPContext  dsp;
//}
//XPSNRCalculator;

pub fn Calculator(comptime T: type) type {
    _ = T;
}

const XPSNRCalculator = struct {
    bpp: isize,
    depth: isize,
    comps: [4]u8,
    numComps: isize,
    numFrames: usize,
    frameRate: usize,
    lineSizes: [4]isize,
    planeHeight: [4]isize,
    planeWidth: [4]isize,
    rgbaMap: [4]u8,
    statsFile: *std.fs.File,
    statsFileStr: ?*c_char,
    sseLuma: ?*f64,
    weights: ?*f64,
    bufOrg: [3]*AVBufferRef,
    bufOrgM1: [3]*AVBufferRef,
    bufOrgM2: [3]*AVBufferRef,
    bufRec: [3]*AVBufferRef,
    maxError64: u64,
    sumWDist: [3]f64,
    sumXPSNR: [3]f64,
    andIsInf: [3]bool,
    isRGB: bool,

    const Self = @This();

    fn calcSquaredError(x: *Self, blkOrg: []i16, blkRec: []i16, strideOrg: isize, strideRec: isize, blockWidth: u32, blockHeight: u32) u64 {
        _ = blockHeight;
        _ = blockWidth;
        _ = strideRec;
        _ = strideOrg;
        _ = blkRec;
        _ = blkOrg;
    }

    //static inline uint64_t calcSquaredError(XPSNRCalculator const *s,
    //                                        const int16_t *blkOrg,     const uint32_t strideOrg,
    //                                        const int16_t *blkRec,     const uint32_t strideRec,
    //                                        const uint32_t blockWidth, const uint32_t blockHeight)
    //{
    //  uint64_t uSSE = 0; /* sum of squared errors */
    //
    //  for (uint32_t y = 0; y < blockHeight; y++)
    //  {
    //    uSSE += s->dsp.sse_line ((const uint8_t*) blkOrg, (const uint8_t*) blkRec, (int) blockWidth);
    //    blkOrg += strideOrg;
    //    blkRec += strideRec;
    //  }
    //
    //  /* return nonweighted sum of squared errors */
    //  return uSSE;
    //}

    //static inline double calcSquaredErrorAndWeight (XPSNRCalculator const *s,
    //                                                const int16_t *picOrg,     const uint32_t strideOrg,
    //                                                int16_t       *picOrgM1,   int16_t       *picOrgM2,
    //                                                const int16_t *picRec,     const uint32_t strideRec,
    //                                                const uint32_t offsetX,    const uint32_t offsetY,
    //                                                const uint32_t blockWidth, const uint32_t blockHeight,
    //                                                const uint32_t bitDepth,   const uint32_t intFrameRate, double *msAct)
    //{
    //  const int      O = (int) strideOrg;
    //  const int      R = (int) strideRec;
    //  const int16_t *o = picOrg   + offsetY*O + offsetX;
    //  int16_t     *oM1 = picOrgM1 + offsetY*O + offsetX;
    //  int16_t     *oM2 = picOrgM2 + offsetY*O + offsetX;
    //  const int16_t *r = picRec   + offsetY*R + offsetX;
    //  const int   bVal = (s->planeWidth[0] * s->planeHeight[0] > 2048 * 1152 ? 2 : 1); /* threshold is a bit more than HD resolution */
    //  const int   xAct = (offsetX > 0 ? 0 : bVal);
    //  const int   yAct = (offsetY > 0 ? 0 : bVal);
    //  const int   wAct = (offsetX + blockWidth  < (uint32_t) s->planeWidth [0] ? (int) blockWidth  : (int) blockWidth  - bVal);
    //  const int   hAct = (offsetY + blockHeight < (uint32_t) s->planeHeight[0] ? (int) blockHeight : (int) blockHeight - bVal);
    //
    //  const double sse = (double) calcSquaredError (s, o, strideOrg,
    //                                                r, strideRec,
    //                                                blockWidth, blockHeight);
    //  uint64_t saAct = 0;  /* spatial abs. activity */
    //  uint64_t taAct = 0; /* temporal abs. activity */
    //
    //  if (wAct <= xAct || hAct <= yAct) /* too tiny */
    //  {
    //    return sse;
    //  }
    //
    //  if (bVal > 1) /* highpass with downsampling */
    //  {
    //    saAct = s->dsp.highds_func (xAct, yAct, wAct, hAct, o, O);
    //  }
    //  else /* <=HD, highpass without downsampling */
    //  {
    //    for (int y = yAct; y < hAct; y++)
    //    {
    //      for (int x = xAct; x < wAct; x++)
    //      {
    //        const int f = 12 * (int)o[y*O + x] - 2 * ((int)o[y*O + x-1] + (int)o[y*O + x+1] + (int)o[(y-1)*O + x] + (int)o[(y+1)*O + x])
    //                        - ((int)o[(y-1)*O + x-1] + (int)o[(y-1)*O + x+1] + (int)o[(y+1)*O + x-1] + (int)o[(y+1)*O + x+1]);
    //        saAct += (uint64_t) abs(f);
    //      }
    //    }
    //  }
    //
    //  /* calculate weight (mean squared activity) */
    //  *msAct = (double) saAct / ((double)(wAct - xAct) * (double)(hAct - yAct));
    //
    //  if (bVal > 1) /* highpass with downsampling */
    //  {
    //    if (intFrameRate <= 32) /* 1st-order diff */
    //    {
    //      taAct = s->dsp.diff1st_func (blockWidth, blockHeight, o, oM1, O);
    //    }
    //    else  /* 2nd-order diff (diff of 2 diffs) */
    //    {
    //      taAct = s->dsp.diff2nd_func (blockWidth, blockHeight, o, oM1, oM2, O);
    //    }
    //  }
    //  else /* <=HD, highpass without downsampling */
    //  {
    //    if (intFrameRate <= 32) /* 1st-order diff */
    //    {
    //      for (uint32_t y = 0; y < blockHeight; y++)
    //      {
    //        for (uint32_t x = 0; x < blockWidth; x++)
    //        {
    //          const int t = (int)o[y*O + x] - (int)oM1[y*O + x];
    //
    //          taAct += XPSNR_GAMMA * (uint64_t) abs(t);
    //          oM1[y*O + x] = o  [y*O + x];
    //        }
    //      }
    //    }
    //    else  /* 2nd-order diff (diff of 2 diffs) */
    //    {
    //      for (uint32_t y = 0; y < blockHeight; y++)
    //      {
    //        for (uint32_t x = 0; x < blockWidth; x++)
    //        {
    //          const int t = (int)o[y*O + x] - 2 * (int)oM1[y*O + x] + (int)oM2[y*O + x];
    //
    //          taAct += XPSNR_GAMMA * (uint64_t) abs(t);
    //          oM2[y*O + x] = oM1[y*O + x];
    //          oM1[y*O + x] = o  [y*O + x];
    //        }
    //      }
    //    }
    //  }
    //
    //  /* weight += mean squared temporal activity */
    //  *msAct += (double) taAct / ((double) blockWidth * (double) blockHeight);
    //
    //  /* lower limit, accounts for high-pass gain */
    //  if (*msAct < (double)(1 << (bitDepth - 6))) *msAct = (double)(1 << (bitDepth - 6));
    //
    //  *msAct *= *msAct; /* because SSE is squared */
    //
    //  /* return nonweighted sum of squared errors */
    //  return sse;
    //}
};

const XPSNR_GAMMA = 2;
const I32x4 = @import("../simd.zig").I32x4;
const I16x8 = @import("../simd.zig").I16x8;
const I16x16 = @import("../simd.zig").I16x16;
// Zig, I hate you for this.

fn mulAddVector(p1: I16x8, p2: I16x8, scale: I16x8, tmp1: *I32x4, tmp2: *I32x4, sum: *isize) void {
    _ = sum;
    _ = tmp2;
    _ = tmp1;
    _ = scale;
    _ = p2;
    _ = p1;
}

fn filterAndDecimateVector(xAct: isize, yAct: isize, wAct: isize, hAct: isize, o: []i16, O: isize) u64 {
    var saAct: u64 = 0;

    if (wAct > 12) {
        const scale1 = I16x8{ 0, 0, -1, -2, -3, -3, -2, -1 };
        const scale2 = I16x8{ 0, 0, -1, -3, 12, 12, -3, -1 };
        const scale3 = I16x8{ 0, 0, 0, -1, -1, -1, -1, 0 };
        var tmp1: I32x4 = @splat(0);
        var tmp2: I32x4 = @splat(0);
        var ym0: I16x8 = @splat(0);
        var yp1: I16x8 = @splat(0);
        var ym1: I16x8 = @splat(0);
        var yp2: I16x8 = @splat(0);
        var ym2: I16x8 = @splat(0);
        var yp3: I16x8 = @splat(0);
        var sum: isize = 0;

        var y: isize = yAct;
        while (y < hAct) : (y += 2) {
            var x: isize = xAct;
            while (x < wAct) : (x += 12) {
                var addr = O * (y - 2) + x - 2;
                var @"y-2": I16x16 = o[addr .. addr + 16].*;
                addr += O;
                var @"y-1": I16x16 = o[addr .. addr + 16].*;
                addr += O;
                var @"y-0": I16x16 = o[addr .. addr + 16].*;
                addr += O;
                var @"y+1": I16x16 = o[addr .. addr + 16].*;
                addr += O;
                var @"y+2": I16x16 = o[addr .. addr + 16].*;
                addr += O;
                var @"y+3": I16x16 = o[addr .. addr + 16].*;

                var xx: isize = 0;
                while (xx < 3) : (xx += 1) {
                    if ((xx << 2) + x < wAct) {
                        sum = 0;
                        ym0 = @as([16]i16, @"y-0")[0..8].*;
                        yp1 = @as([16]i16, @"y+1")[0..8].*;
                        mulAddVector(ym0, yp1, scale2, &tmp1, &tmp2, &sum);
                        ym1 = @as([16]i16, @"y-1")[0..8].*;
                        yp2 = @as([16]i16, @"y+2")[0..8].*;
                        mulAddVector(ym1, yp2, scale1, &tmp1, &tmp2, &sum);
                        ym2 = @as([16]i16, @"y-2")[0..8].*;
                        yp3 = @as([16]i16, @"y+3")[0..8].*;
                        mulAddVector(ym2, yp3, scale3, &tmp1, &tmp2, &sum);
                        saAct += @as(u64, @abs(sum));
                    }
                    if ((xx << 2) + x + 2 < wAct) {
                        sum = 0;
                        ym0 = math.shr(I16x8, ym0, 2);
                        yp1 = math.shr(I16x8, yp1, 2);
                        mulAddVector(ym0, yp1, scale2, &tmp1, &tmp2, &sum);
                        ym1 = math.shr(I16x8, ym1, 2);
                        yp2 = math.shr(I16x8, yp2, 2);
                        mulAddVector(ym1, yp2, scale1, &tmp1, &tmp2, &sum);
                        ym2 = math.shr(I16x8, ym2, 2);
                        yp3 = math.shr(I16x8, yp3, 2);
                        mulAddVector(ym2, yp3, scale3, &tmp1, &tmp2, &sum);
                        saAct += @as(u64, @abs(sum));

                        @"y-0" = math.shr(I16x16, @"y-0", 2);
                        @"y+1" = math.shr(I16x16, @"y+1", 2);
                        @"y-1" = math.shr(I16x16, @"y-1", 2);
                        @"y+2" = math.shr(I16x16, @"y+2", 2);
                        @"y-2" = math.shr(I16x16, @"y-2", 2);
                        @"y+3" = math.shr(I16x16, @"y+3", 2);
                    }
                }
            }
        }
    } else {
        saAct = filterAndDecimateScalar(xAct, yAct, wAct, hAct, o, O); // Input too small for SIMD
    }
    return saAct;
}

fn filterAndDecimateScalar(xAct: isize, yAct: isize, wAct: isize, hAct: isize, o: []i16, O: isize) u64 {
    var saAct: u64 = 0;
    var y: isize = yAct;
    while (y < hAct) : (y += 2) {
        var x: isize = xAct;
        while (x < wAct) : (x += 2) {
            // zig fmt: off
            const f = 12 * (
                @as(isize, o[O *  y      + x    ]) + @as(isize, o[O *  y      + x + 1]) +
                @as(isize, o[O * (y + 1) + x    ]) + @as(isize, o[O * (y + 1) + x + 1])
            ) - 3 * (
                @as(isize, o[O * (y - 1) + x    ]) + @as(isize, o[O * (y - 1) + x + 1]) +
                @as(isize, o[O * (y + 2) + x    ]) + @as(isize, o[O * (y + 2) + x + 1])
            ) - 3 * (
                @as(isize, o[O *  y      + x - 1]) + @as(isize, o[O *  y      + x + 2]) +
                @as(isize, o[O * (y + 1) + x - 1]) + @as(isize, o[O * (y + 1) + x + 2])
            ) - 2 * (
                @as(isize, o[O * (y - 1) + x - 1]) + @as(isize, o[O * (y - 1) + x + 2]) +
                @as(isize, o[O * (y + 2) + x - 1]) + @as(isize, o[O * (y + 2) + x + 2])
            ) - (
                @as(isize, o[O * (y - 2) + x - 1]) + @as(isize, o[O * (y - 2) + x    ]) +
                @as(isize, o[O * (y - 2) + x + 1]) + @as(isize, o[O * (y - 2) + x + 2]) +
                @as(isize, o[O * (y + 3) + x - 1]) + @as(isize, o[O * (y + 3) + x    ]) +
                @as(isize, o[O * (y + 3) + x + 1]) + @as(isize, o[O * (y + 3) + x + 2]) +
                @as(isize, o[O * (y - 1) + x - 2]) + @as(isize, o[O *  y      + x - 2]) +
                @as(isize, o[O * (y + 1) + x - 2]) + @as(isize, o[O * (y + 2) + x - 2]) +
                @as(isize, o[O * (y - 1) + x + 3]) + @as(isize, o[O *  y      + x + 3]) +
                @as(isize, o[O * (y + 1) + x + 3]) + @as(isize, o[O * (y + 2) + x + 3])
            );
            // zig fmt: on
            saAct += @as(u64, @abs(f));
        }
    }
    return saAct;
}

fn diff1stScalar(wAct: u32, hAct: u32, o: []i16, oM1: []i16, O: isize) u64 {
    var taAct: u64 = 0;
    var y: i32 = 0;
    while (y < hAct) : (y += 2) {
        var x: i32 = 0;
        while (x < wAct) : (x += 2) {
            // zig fmt: off
            const t = (
                @as(isize, o  [O *  y      + x    ]) + @as(isize, o  [O *  y      + x + 1]) +
                @as(isize, o  [O * (y + 1) + x    ]) + @as(isize, o  [O * (y + 1) + x + 1])
            ) - (
                @as(isize, oM1[O *  y      + x    ]) + @as(isize, oM1[O *  y      + x + 1]) +
                @as(isize, oM1[O * (y + 1) + x    ]) + @as(isize, oM1[O * (y + 1) + x + 1])
            );
            taAct += @as(u64, @abs(t));

            oM1[O *  y      + x    ] = o[O *  y      + x    ];
            oM1[O *  y      + x + 1] = o[O *  y      + x + 1];
            oM1[O * (y + 1) + x    ] = o[O * (y + 1) + x    ];
            oM1[O * (y + 1) + x + 1] = o[O * (y + 1) + x + 1];
            // zig fmt: on
        }
    }
    return taAct * XPSNR_GAMMA;
}

fn diff2ndScalar(wAct: u32, hAct: u32, o: []i16, oM1: []i16, oM2: []i16, O: isize) u64 {
    var taAct: u64 = 0;
    var y: i32 = 0;
    while (y < hAct) : (y += 2) {
        var x: i32 = 0;
        while (x < wAct) : (x += 2) {
            // zig fmt: off
            const t = (
                @as(isize, o  [O *  y      + x    ]) + @as(isize, o  [O *  y      + x + 1]) +
                @as(isize, o  [O * (y + 1) + x    ]) + @as(isize, o  [O * (y + 1) + x + 1])
            ) - 2 * (
                @as(isize, oM1[O *  y      + x    ]) + @as(isize, oM1[O *  y      + x + 1]) +
                @as(isize, oM1[O * (y + 1) + x    ]) + @as(isize, oM1[O * (y + 1) + x + 1])
            ) + (
                @as(isize, oM2[O *  y      + x    ]) + @as(isize, oM2[O *  y      + x + 1]) +
                @as(isize, oM2[O * (y + 1) + x    ]) + @as(isize, oM2[O * (y + 1) + x + 1])
            );
            taAct += @as(u64, @abs(t));

            oM2[O *  y      + x    ] = oM1[O *  y      + x    ];
            oM2[O *  y      + x + 1] = oM1[O *  y      + x + 1];
            oM2[O * (y + 1) + x    ] = oM1[O * (y + 1) + x    ];
            oM2[O * (y + 1) + x + 1] = oM1[O * (y + 1) + x + 1];
            oM1[O *  y      + x    ] = o  [O *  y      + x    ];
            oM1[O *  y      + x + 1] = o  [O *  y      + x + 1];
            oM1[O * (y + 1) + x    ] = o  [O * (y + 1) + x    ];
            oM1[O * (y + 1) + x + 1] = o  [O * (y + 1) + x + 1];
            // zig fmt: on
        }
    }
    return taAct * XPSNR_GAMMA;
}

fn sseLine16b(blkOrg8: []u8, blkRec8: []u8, blockWidth: isize) u64 {
    const blkOrg: []u16 = @ptrCast(blkOrg8);
    const blkRec: []u16 = @ptrCast(blkRec8);
    var lSSE: u64 = 0;
    var x: isize = 0;
    while (x < blockWidth) : (x += 1) {
        const err = @as(i64, blkOrg[x]) - @as(i64, blkRec[x]);
        lSSE += @as(u64, err * err);
    }
    return lSSE;
}
