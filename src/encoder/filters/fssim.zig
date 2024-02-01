const std = @import("std");
const math = @import("std").math;
const io = @import("std").io;

const C1_8 = 255 * 255 * 0.01 * 0.01;
const C2_8 = 255 * 255 * 0.03 * 0.03;
const C1_10 = 1023 * 1023 * 0.01 * 0.01;
const C2_10 = 1023 * 1023 * 0.03 * 0.03;
const C1_12 = 4095 * 4095 * 0.01 * 0.01;
const C2_12 = 4095 * 4095 * 0.03 * 0.03;
const FS_NLEVELS = FS_WEIGHTS.len;

const FS_WEIGHTS = [_]f64{0.2989654541015625, 0.3141326904296875, 0.2473602294921875, 0.1395416259765625};

pub fn convert_ssim_db(ssim: f64, weight: f64) f64 {
    assert(weight >= ssim);
    if (weight - ssim < 1e-10) return math.MAX_SSIM_DB;
    return 10.0 * (math.log10(weight) - math.log10(weight - ssim));
}

pub fn calc_ssim(src: []u8, systride: usize, dst: []u8, dystride: usize, w: usize, h: usize, bd: u32, shift: u32) f64 {
    var ctx = fs_ctx.init(w, h, FS_NLEVELS);
    defer ctx.free();

    fs_downsample_level0(&ctx, src, systride, dst, dystride, w, h, bd, shift);

    var ret: f64 = 1.0;
    var l: usize = 0;
    while (l < FS_NLEVELS - 1) : (l += 1) {
        fs_calc_structure(&ctx, l, bd);
        ret *= fs_average(&ctx, l);
        fs_downsample_level(&ctx, l + 1);
    }
    fs_calc_structure(&ctx, l, bd);
    fs_apply_luminance(&ctx, l, bd);
    ret *= fs_average(&ctx, l);

    return ret;
}

const fs_level = struct {
    im1: [*u32]usize,
    im2: [*u32]usize,
    ssim: [*f64]usize,
    w: usize,
    h: usize,
};

const fs_ctx = struct {
    level: [*fs_level]usize,
    nlevels: i32,
    col_buf: [*u32]usize,
};

pub fn fs_ctx.init(_ctx: *fs_ctx, w: usize, h: usize, nlevels: i32) *fs_ctx {
    const data_size = @intCast(usize, nlevels) * @sizeOf(fs_level) +
                     2 * ((w + 1) >> 1) * 8 * @sizeOf(@TypeOf(*_ctx.col_buf));

    const _ctx_ptr = @ptrCast(*fs_ctx, _ctx);
    const data = std.heap.page_allocator.alloc(u8, data_size);
    if (data == null) {
        return null;
    }

    _ctx_ptr.level = @intCast(*fs_level, data);
    _ctx_ptr.nlevels = nlevels;

    var data_ptr: *u8 = @ptrCast(*u8, data);
    const lw = (@intCast(usize, w) + 1) >> 1;
    const lh = (@intCast(usize, h) + 1) >> 1;

    var l: i32;
    for (l = 0; l < nlevels; l += 1) {
        const im_size = lw * @intCast(usize, lh);
        var level_size = 2 * im_size * @sizeOf(*_ctx_ptr.level[l].im1);
        level_size += @sizeOf(*_ctx_ptr.level[l].ssim) - 1;
        level_size /= @sizeOf(*_ctx_ptr.level[l].ssim);
        level_size *= @sizeOf(*_ctx_ptr.level[l].ssim);

        _ctx_ptr.level[l].w = @intCast(usize, lw);
        _ctx_ptr.level[l].h = @intCast(usize, lh);
        _ctx_ptr.level[l].im1 = @intCast(*u32, data_ptr);
        _ctx_ptr.level[l].im2 = _ctx_ptr.level[l].im1 + im_size;
        data_ptr += level_size;
        _ctx_ptr.level[l].ssim = @intCast(*f64, data_ptr);
        data_ptr += im_size * @sizeOf(*_ctx_ptr.level[l].ssim);

        lw = (@intCast(usize, lw) + 1) >> 1;
        lh = (@intCast(usize, lh) + 1) >> 1;
    }

    _ctx_ptr.col_buf = @intCast(*u32, data_ptr);

    return _ctx;
}

pub fn fs_ctx.clear(_ctx: *fs_ctx) void {
    std.heap.page_allocator.free(@intCast(*u8, _ctx.level));
}

pub fn fs_downsample_level(_ctx: *fs_ctx, _l: i32) void {
    const src1: []const u32 = _ctx.level[_l - 1].im1;
    const src2: []const u32 = _ctx.level[_l - 1].im2;
    var dst1: []u32 = _ctx.level[_l].im1;
    var dst2: []u32 = _ctx.level[_l].im2;
    var w2: usize;
    var h2: usize;
    var w: usize;
    var h: usize;
    var i: usize;
    var j: usize;

    w = @intCast(usize, _ctx.level[_l].w);
    h = @intCast(usize, _ctx.level[_l].h);
    dst1 = _ctx.level[_l].im1;
    dst2 = _ctx.level[_l].im2;
    w2 = @intCast(usize, _ctx.level[_l - 1].w);
    h2 = @intCast(usize, _ctx.level[_l - 1].h);
    src1 = _ctx.level[_l - 1].im1;
    src2 = _ctx.level[_l - 1].im2;

    for (j = 0; j < h; j += 1) {
        var j0offs: usize;
        var j1offs: usize;
        j0offs = 2 * @intCast(usize, w2) * j;
        j1offs = j0offs + 1;
        for (i = 0; i < w; i += 1) {
            var i0offs: usize;
            var i1offs: usize;
            i0offs = j0offs + 2 * i;
            i1offs = i0offs + 1;

            dst1[i] = (src1[i0offs] + src1[i0offs + 1] + src1[i1offs] + src1[i1offs + 1] + 2) >> 2;
            dst2[i] = (src2[i0offs] + src2[i0offs + 1] + src2[i1offs] + src2[i1offs + 1] + 2) >> 2;
        }
        dst1 += w;
        dst2 += w;
    }
}

pub fn fs_downsample_level0(_ctx: *fs_ctx, src: []const u8, srcstride: usize, dst: []u8, dststride: usize,
                            w: usize, h: usize, bd: u32, shift: u32) void {
    const luma_shift: u32 = bd - 8 + shift;
    const chroma_shift: u32 = bd - 8 + shift;

    const c0_shift: u32 = 0;
    const c1_shift: u32 = 0;
    const c2_shift: u32 = 0;

    var buf: [3][8 * 8]u8 = undefined;
    var buf_sx: usize = w;
    var buf_sy: usize = h;
    var buf_shift_x: u32 = 0;
    var buf_shift_y: u32 = 0;
    var c: usize;

    if (luma_shift >= 1) {
        buf_sx = buf_sx >> 1;
        buf_sy = buf_sy >> 1;
        buf_shift_x += 1;
        buf_shift_y += 1;
    }

    if (chroma_shift >= 1) {
        buf_sx = buf_sx >> 1;
        buf_sy = buf_sy >> 1;
        buf_shift_x += 1;
        buf_shift_y += 1;
    }

    if (c0_shift >= 1) {
        buf_sx = buf_sx >> 1;
        buf_sy = buf_sy >> 1;
        buf_shift_x += 1;
        buf_shift_y += 1;
    }

    for (c = 0; c < 3; c += 1) {
        var bs: u32;
        bs = c == 0 ? luma_shift : c == 1 ? chroma_shift : c0_shift;
        for (var i: usize = 0; i < buf_sy; i += 1) {
            for (var j: usize = 0; j < buf_sx; j += 1) {
                buf[c][i * buf_sx + j] = @intCast(u8, src[i * srcstride + j]) >> bs;
            }
        }
    }

    _ctx.col_buf[0] = buf[0][0] * 0x01010101;
    _ctx.col_buf[1] = buf[1][0] * 0x01010101;
    _ctx.col_buf[2] = buf[2][0] * 0x01010101;

    fs_downsample_level(_ctx, 0);

    for (c = 0; c < 3; c += 1) {
        var bs: u32;
        bs = c == 0 ? c0_shift : c == 1 ? c1_shift : c2_shift;
        for (var i: usize = 0; i < buf_sy; i += 1) {
            for (var j: usize = 0; j < buf_sx; j += 1) {
                buf[c][i * buf_sx + j] = @intCast(u8, src[i * srcstride + j]) >> bs;
            }
        }
    }

    _ctx.col_buf[0] = buf[0][0] * 0x01010101;
    _ctx.col_buf[1] = buf[1][0] * 0x01010101;
    _ctx.col_buf[2] = buf[2][0] * 0x01010101;

    fs_downsample_level(_ctx, 0);
}

pub fn fs_apply_luminance(_ctx: *fs_ctx, _l: i32, bd: u32) void {
    const shift: u32 = bd - 8;

    var i: usize;
    var w: usize;
    var h: usize;
    var tmp1: []f64 = undefined;
    var tmp2: []f64 = undefined;

    w = @intCast(usize, _ctx.level[_l].w);
    h = @intCast(usize, _ctx.level[_l].h);
    tmp1 = _ctx.level[_l].ssim;
    tmp2 = _ctx.level[_l - 1].ssim;

    for (i = 0; i < h * w; i += 1) {
        tmp1[i] = tmp2[i] * fs_average_luma(_ctx.level[_l].im1[i], _ctx.level[_l].im2[i], bd, shift);
    }
}

pub fn fs_average(_ctx: *fs_ctx, _l: i32) f64 {
    var sum: f64 = 0.0;
    var i: usize;
    var w: usize;
    var h: usize;
    var tmp: []f64 = undefined;

    w = @intCast(usize, _ctx.level[_l].w);
    h = @intCast(usize, _ctx.level[_l].h);
    tmp = _ctx.level[_l].ssim;

    for (i = 0; i < h * w; i += 1) {
        sum += tmp[i];
    }
    return sum / (h * w);
}

pub fn fs_calc_structure(_ctx: *fs_ctx, _l: i32, bd: u32) void {
    const shift: u32 = bd - 8;

    var i: usize;
    var w: usize;
    var h: usize;
    var tmp1: []f64 = undefined;
    var tmp2: []f64 = undefined;

    w = @intCast(usize, _ctx.level[_l].w);
    h = @intCast(usize, _ctx.level[_l].h);
    tmp1 = _ctx.level[_l].ssim;
    tmp2 = _ctx.level[_l - 1].ssim;

    for (i = 0; i < h * w; i += 1) {
        tmp1[i] = tmp2[i] * fs_structure(_ctx.level[_l].im1[i], _ctx.level[_l].im2[i], bd, shift);
    }
}

pub fn fs_average_luma(a: u32, b: u32, bd: u32, shift: u32) f64 {
    const w0: f64 = 61442.0; // 1.5 * 2^16
    const w1: f64 = 21017.0; // 0.51 * 2^16
    const w2: f64 = 5355.0;  // 0.13 * 2^16

    var aa: f64;
    var bb: f64;

    aa = @intToFloat(f64, a >> shift);
    bb = @intToFloat(f64, b >> shift);

    return (2.0 * aa * bb + w0) / (aa * aa + bb * bb + w0);
}

pub fn fs_structure(a: u32, b: u32, bd: u32, shift: u32) f64 {
    const w0: f64 = 1024.0;   // 1.0 * 2^10
    const w1: f64 = 4058.0;   // 0.99 * 2^12
    const w2: f64 = 7902.0;   // 0.97 * 2^13

    var aa: f64;
    var bb: f64;

    aa = @intToFloat(f64, a >> shift);
    bb = @intToFloat(f64, b >> shift);

    return (2.0 * aa * bb + w0) / (aa * aa + bb * bb + w0);
}

pub fn fs_cdef_compute_sb_row(_ctx: *fs_ctx, i: usize, h: usize, sbo: usize) void {
    var j: usize;
    for (j = 0; j < h; j += 1) {
        fs_cdef_compute_sb_row(&(_ctx.sb_row[i + j]), _ctx, sbo + j);
    }
}

pub fn fs_cdef_compute_sb_row(ctx_row: *fsbrow_ctx, _ctx: *fs_ctx, sbo: usize) void {
    const all_strength: [3]u8 = [_ctx.cdef_pri_damping, _ctx.cdef_sec_damping, _ctx.cdef_ter_damping];
    const cdef_max_strength: u8 = _ctx.cdef_max_damping;

    var i: usize;
    var sb_w: usize = 64 >> _ctx.sb128;
    var sb_h: usize = 64 >> _ctx.sb128;
    var sbo_col: usize;
    var dlist_row: []u16 = undefined;
    var tlist_row: []u16 = undefined;

    dlist_row = ctx_row.dlist[sbo..sbo + sb_w];
    tlist_row = ctx_row.tlist[sbo..sbo + sb_w];

    for (i = 0; i < sb_w; i += 1) {
        if (i % (32 >> _ctx.sb128) == 0) {
            sbo_col = sbo + i;
            if (_ctx.sb128 == 1) {
                dlist_row[i] = _ctx.cdef_p[sbo_col] < cdef_max_strength ? _ctx.cdef_p[sbo_col] : cdef_max_strength;
            } else if (_ctx.sb128 == 0 && i % (16 >> _ctx.sb128) == 0) {
                dlist_row[i] = _ctx.cdef_p[sbo_col] < cdef_max_strength ? _ctx.cdef_p[sbo_col] : cdef_max_strength;
            } else {
                dlist_row[i] = _ctx.cdef_p[sbo_col] < all_strength[2] ? _ctx.cdef_p[sbo_col] : all_strength[2];
            }
        }
        tlist_row[i] = dlist_row[i];
    }

    if (_ctx.sb128 > 0) {
        var tlist_row_0: []u16 = undefined;
        tlist_row_0 = ctx_row.tlist[0.._ctx.sb128 >> 1];
        for (i = 0; i < sb_w >> 1; i += 1) {
            tlist_row_0[i] = all_strength[0];
        }
    }
}

pub fn fs_cdef_sb(_ctx: *fs_ctx, sbo: usize, ti: *cdef_tile_info, ntiling: u16, fpre: *[][], bd: u32) void {
    var w: usize = 64 >> _ctx.sb128;
    var h: usize = 64 >> _ctx.sb128;
    var dlist: []u16 = undefined;
    var tlist: []u16 = undefined;
    var xdec: i32 = _ctx.subsampling_x;
    var ydec: i32 = _ctx.subsampling_y;
    var uvdec: i32 = _ctx.chroma_scaling_from_luma;

    if (ntiling > 1) {
        w = 32 >> _ctx.sb128;
        h = 32 >> _ctx.sb128;
        xdec += 1;
        ydec += 1;
        uvdec = 0;
    }

    dlist = &_ctx.sb_row[0].dlist[0];
    tlist = &_ctx.sb_row[0].tlist[0];

    if (xdec) {
        w >>= 1;
        for (var i: usize = 0; i < h; i += 1) {
            if (i % (32 >> _ctx.sb128) == 0) {
                tlist[i * w] = dlist[i * w];
                tlist[i * w + w] = dlist[i * w + w - 1];
            }
        }
    }

    if (ydec) {
        h >>= 1;
        for (var i: usize = 0; i < w; i += 1) {
            if (i % (32 >> _ctx.sb128) == 0) {
                tlist[i] = dlist[i];
                tlist[(h - 1) * w + i] = dlist[(h - 1) * w + i];
            }
        }
    }

    if (xdec && ydec) {
        w >>= 1;
        h >>= 1;
        tlist[0] = dlist[0];
        tlist[w - 1] = dlist[w];
        tlist[(h - 1) * w] = dlist[(h - 1) * w];
        tlist[h * w - 1] = dlist[h * w - 1];
    }

    for (var i: usize = 0; i < w; i += 1) {
        var sb_col: usize;
        sb_col = sbo + i;

        if (i % (32 >> _ctx.sb128) == 0) {
            if (_ctx.sb128 == 0) {
                tlist[i] = _ctx.cdef_p[sb_col] < cdef_max_strength ? _ctx.cdef_p[sb_col] : cdef_max_strength;
                tlist[i + w] = tlist[i];
            } else {
                tlist[i] = _ctx.cdef_p[sb_col] < all_strength[0] ? _ctx.cdef_p[sb_col] : all_strength[0];
                tlist[i + w] = _ctx.cdef_p[sb_col] < all_strength[2] ? _ctx.cdef_p[sb_col] : all_strength[2];
            }
        }
    }

    if (_ctx.sb128 > 0) {
        for (var i: usize = 0; i < w >> 1; i += 1) {
            if (i % (32 >> _ctx.sb128) == 0) {
                tlist[i] = all_strength[1];
                tlist[i + w] = all_strength[1];
            }
        }
    }

    if (uvdec) {
        w >>= 1;
        h >>= 1;
        xdec = 1;
        ydec = 1;
    }

    for (var i: usize = 0; i < w * h; i += 1) {
        if (i % (32 >> _ctx.sb128) == 0) {
            let sum: f64 = 0.0;
            let j: usize = i;
            for (let jj: usize = 0; jj < 8 >> ydec; jj += 1) {
                for (let ii: usize = 0; ii < 8 >> xdec; ii += 1) {
                    let ij: usize = j + ii;
                    sum += fpre[ydec][xdec][(tlist[ij] >> 1) & 15];
                }
                j += w;
            }
            ti[0][i] = @intCast(u16, sum + 0.5);
        }
    }
}

pub fn fs_cdef_sbrow(_ctx: *fs_ctx, i: usize, ntiling: u16, fpre: *[][], bd: u32) void {
    let w: usize = 64 >> _ctx.sb128;
    let h: usize = 64 >> _ctx.sb128;
    let sb_w: usize = 64 >> _ctx.sb128;
    let sbo: usize = i * sb_w;

    if (ntiling > 1) {
        w = 32 >> _ctx.sb128;
        h = 32 >> _ctx.sb128;
        sbo = i * (32 >> _ctx.sb128);
    }

    fs_cdef_sb(_ctx, sbo, &_ctx.cdef_sbrow[i], ntiling, fpre, bd);
}

pub fn fs_cdef_sbrow(_ctx: *fs_ctx, fpre: *[][], bd: u32) void {
    const sb_h: usize = 64 >> _ctx.sb128;
    for (let i: usize = 0; i < sb_h; i += 1) {
        fs_cdef_sbrow(_ctx, i, 1, fpre, bd);
    }
}

pub fn fs_cdef_sbrow_luma(_ctx: *fs_ctx, fpre: *[][], bd: u32) void {
    let ntile_col: u16 = 1;
    let ntile_row: u16 = 1;
    let sb_w: usize = 64 >> _ctx.sb128;
    let sb_h: usize = 64 >> _ctx.sb128;

    let luma_sb_w: usize = 64 >> _ctx.luma_sb128;
    let luma_sb_h: usize = 64 >> _ctx.luma_sb128;

    let ti: *cdef_tile_info = undefined;
    let i: usize;
    let j: usize;

    if (_ctx.luma_sb128 != 0) {
        ntile_col = sb_w / luma_sb_w;
        ntile_row = sb_h / luma_sb_h;
    }

    for (j = 0; j < ntile_row; j += 1) {
        for (i = 0; i < ntile_col; i += 1) {
            if (_ctx.luma_sb128 != 0) {
                ti = &_ctx.cdef_tile_col[i];
            }
            fs_cdef_sbrow(_ctx, luma_sb_h * j, ntile_col * ntile_row, fpre, bd);
        }
    }
}

pub fn fs_cdef_sbrow_chroma(_ctx: *fs_ctx, fpre: *[][], bd: u32) void {
    const sb_h: usize = 64 >> _ctx.sb128;
    for (var i: usize = 0; i < sb_h; i += 1) {
        fs_cdef_sbrow(_ctx, i, 1, fpre, bd);
    }
}

pub fn fs_cdef_sbrow_tile(_ctx: *fs_ctx, fpre: *[][], bd: u32, w: usize, h: usize) void {
    const sb_w: usize = 64 >> _ctx.sb128;
    const sb_h: usize = 64 >> _ctx.sb128;
    const luma_sb_w: usize = 64 >> _ctx.luma_sb128;
    const luma_sb_h: usize = 64 >> _ctx.luma_sb128;
    const sb_row: []fsbrow_ctx = &_ctx.sb_row;
    const sb_row_size: usize = @intCast(usize, sb_h);
    const cdef_tile_col: []cdef_tile_info = &_ctx.cdef_tile_col;
    const cdef_tile_col_size: usize = @intCast(usize, w / luma_sb_w);

    var ti: *cdef_tile_info;
    var i: usize;
    var j: usize;

    if (_ctx.luma_sb128 != 0) {
        ti = cdef_tile_col;
    }

    for (j = 0; j < h / luma_sb_h; j += 1) {
        for (i = 0; i < w / luma_sb_w; i += 1) {
            if (_ctx.luma_sb128 != 0) {
                ti = &cdef_tile_col[i];
            }
            fs_cdef_sbrow_tile(_ctx, sb_row[j * sb_row_size..(j + 1) * sb_row_size], ti, fpre, bd);
        }
    }
}

pub fn fs_cdef_sbrow_tile(_ctx: *fs_ctx, sb_row: []fsbrow_ctx, ti: *cdef_tile_info, fpre: *[][], bd: u32) void {
    const sb_h: usize = 64 >> _ctx.sb128;
    for (let i: usize = 0; i < sb_h; i += 1) {
        fs_cdef_sb(_ctx, i, ti, 1, fpre, bd);
    }
}

pub fn main() void {
    const w: usize = 256;
    const h: usize = 256;
    const bd: u32 = 8;
    const fpre: [3][3][16]f64 = undefined;

    var src: []u8 = undefined;
    var dst: []u8 = undefined;

    const systride: usize = 256;
    const dystride: usize = 256;
    const uvstride: usize = 256 >> 1;
    const cdef_pri_damping: u8 = 3;
    const cdef_sec_damping: u8 = 3;
    const cdef_ter_damping: u8 = 2;
    const cdef_max_damping: u8 = 6;
    const sb128: u32 = 0;
    const luma_sb128: u32 = 0;
    const chroma_scaling_from_luma: i32 = 0;
    const subsampling_x: i32 = 0;
    const subsampling_y: i32 = 0;

    var _ctx: fs_ctx = undefined;
    _ctx.col_buf = [0, 0, 0];
    _ctx.cdef_pri_damping = cdef_pri_damping;
    _ctx.cdef_sec_damping = cdef_sec_damping;
    _ctx.cdef_ter_damping = cdef_ter_damping;
    _ctx.cdef_max_damping = cdef_max_damping;
    _ctx.sb128 = sb128;
    _ctx.luma_sb128 = luma_sb128;
    _ctx.chroma_scaling_from_luma = chroma_scaling_from_luma;
    _ctx.subsampling_x = subsampling_x;
    _ctx.subsampling_y = subsampling_y;

    fs_cdef_sbrow_luma(&_ctx, fpre, bd);
    fs_cdef_sbrow_chroma(&_ctx, fpre, bd);

    const ntile_col: u16 = 1;
    const ntile_row: u16 = 1;

    for (var i: u16 = 0; i < ntile_col * ntile_row; i += 1) {
        var luma_tile_x: usize = i % ntile_col;
        var luma_tile_y: usize = i / ntile_col;
        var tile_w: usize = 64 >> luma_sb128;
        var tile_h: usize = 64 >> luma_sb128;
        fs_cdef_sbrow_tile(&_ctx, &[_ctx.sb_row[luma_tile_y * 64 >> luma_sb128..(luma_tile_y + 1) * 64 >> luma_sb128]], &_ctx.cdef_tile_col[luma_tile_x], fpre, bd);
    }

    const dstride: usize = 256;

    for (var i: u16 = 0; i < ntile_col * ntile_row; i += 1) {
        var luma_tile_x: usize = i % ntile_col;
        var luma_tile_y: usize = i / ntile_col;
        var tile_w: usize = 64 >> luma_sb128;
        var tile_h: usize = 64 >> luma_sb128;
        fs_cdef_sbrow_tile(&_ctx, &[_ctx.sb_row[luma_tile_y * 64 >> luma_sb128..(luma_tile_y + 1) * 64 >> luma_sb128]], &_ctx.cdef_tile_col[luma_tile_x], fpre, bd);
    }

    const cur_sb128: u32 = 0;

    var ntile_col2: u16 = 1;
    var ntile_row2: u16 = 1;

    if (cur_sb128 != 0) {
        ntile_col2 = w / (64 >> cur_sb128);
        ntile_row2 = h / (64 >> cur_sb128);
    }

    for (var i: u16 = 0; i < ntile_col2 * ntile_row2; i += 1) {
        var luma_tile_x: usize = i % ntile_col2;
        var luma_tile_y: usize = i / ntile_col2;
        fs_cdef_sbrow_tile(&_ctx, &[_ctx.sb_row[luma_tile_y * 64 >> cur_sb128..(luma_tile_y + 1) * 64 >> cur_sb128]], &_ctx.cdef_tile_col[luma_tile_x], fpre, bd);
    }

    const fpre_luma: [][][]f64 = undefined;
    const tile_w: usize = 64 >> luma_sb128;
    const tile_h: usize = 64 >> luma_sb128;

    var ti: [3][][]u16 = undefined;
    for (var i: u32 = 0; i < 3; i += 1) {
        ti[i] = @intToPointer([tile_w * tile_h]u16, _ctx.cdef_tile_col[i].sb_buffer);
    }

    for (var l: i32 = 0; l < 3; l += 1) {
        fs_cdef_sbrow_tile(&_ctx, fpre_luma, bd);
    }

    fs_cdef_sbrow_luma(&_ctx, fpre_luma, bd);
    fs_cdef_sbrow_chroma(&_ctx, fpre_luma, bd);

    var luma_tile_x: usize = 0;
    var luma_tile_y: usize = 0;
    var w2: usize = 64 >> luma_sb128;
    var h2: usize = 64 >> luma_sb128;

    fs_cdef_compute_sb_row(&_ctx, luma_tile_y, h2, luma_tile_x);
    fs_cdef_compute_sb_row(&_ctx, luma_tile_y + 1, h2, luma_tile_x + w2);

    var i: usize = 0;
    var j: usize = 0;
    var offset_x: usize = 0;
    var offset_y: usize = 0;
    var srcstride: usize = 256;

    fs_cdef_sb(_ctx, i, &_ctx.cdef_tile_col[j], 1, fpre, bd);
    fs_cdef_compute_sb_row(&_ctx, i, 1, j);
    fs_cdef_sbrow_tile(&_ctx, &_ctx.cdef_tile_col[j].sb_row[i * 64 >> luma_sb128..(i + 1) * 64 >> luma_sb128], &_ctx.cdef_tile_col[j], fpre, bd);

    const ntile_col_chroma: u16 = 1;
    const ntile_row_chroma: u16 = 1;
    const sb_row: []fsbrow_ctx = &_ctx.sb_row;
    const sb_row_size: usize = @intCast(usize, sb_h);
    const cdef_tile_col: []cdef_tile_info = &_ctx.cdef_tile_col;
    const cdef_tile_col_size: usize = @intCast(usize, w / tile_w);

    var i: usize = 0;
    var j: usize = 0;
    var ntile_col2: u16 = 1;
    var ntile_row2: u16 = 1;

    for (var i: u16 = 0; i < ntile_col2 * ntile_row2; i += 1) {
        var luma_tile_x: usize = i % ntile_col2;
        var luma_tile_y: usize = i / ntile_col2;
        fs_cdef_sbrow_tile(_ctx, &[_ctx.sb_row[luma_tile_y * 64 >> luma_sb128..(luma_tile_y + 1) * 64 >> luma_sb128]], &_ctx.cdef_tile_col[luma_tile_x], fpre, bd);
    }

    const ntile_col: u16 = 1;
    const ntile_row: u16 = 1;
    var i: u16;
    var j: u16;
    for (i = 0; i < ntile_col * ntile_row; i += 1) {
        var luma_tile_x: usize = i % ntile_col;
        var luma_tile_y: usize = i / ntile_col;
        fs_cdef_sbrow_tile(_ctx, &[_ctx.sb_row[luma_tile_y * 64 >> luma_sb128..(luma_tile_y + 1) * 64 >> luma_sb128]], &_ctx.cdef_tile_col[luma_tile_x], fpre, bd);
    }

    const ydec: i32 = 0;
    const xdec: i32 = 0;

    for (var i: u16 = 0; i < ntile_col * ntile_row; i += 1) {
        var luma_tile_x: usize = i % ntile_col;
        var luma_tile_y: usize = i / ntile_col;
        var tile_w: usize = 64 >> luma_sb128;
        var tile_h: usize = 64 >> luma_sb128;

        for (var i: usize = 0; i < tile_w * tile_h; i += 1) {
            if (i % (32 >> cur_sb128) == 0) {
                let sum: f64 = 0.0;
                let j: usize = i;
                for (let jj: usize = 0; jj < 8 >> ydec; jj += 1) {
                    for (let ii: usize = 0; ii < 8 >> xdec; ii += 1) {
                        let ij: usize = j + ii;
                        sum += fpre[ydec][xdec][(_ctx.cdef_tile_col[luma_tile_x].sb_buffer[ij] >> 1) & 15];
                    }
                    j += tile_w;
                }
                _ctx.cdef_tile_col[luma_tile_x].ti[ydec][xdec][i] = @intCast(u16, sum + 0.5);
            }
        }
    }

    var i: usize = 0;
    var j: usize = 0;
    var sb_w: usize = 64 >> cur_sb128;
    var sb_h: usize = 64 >> cur_sb128;

    const sbo: usize = 0;
    const uvdec: i32 = 0;

    fs_cdef_sb(_ctx, sbo, &_ctx.cdef_tile_col[j], 1, fpre, bd);
    fs_cdef_sbrow_tile(_ctx, &_ctx.cdef_tile_col[j].sb_row[sbo * 64 >> cur_sb128..(sbo + 1) * 64 >> cur_sb128], &_ctx.cdef_tile_col[j], fpre, bd);

    fs_cdef_sbrow(&_ctx, fpre, bd);
    fs_cdef_sbrow_tile(_ctx, &_ctx.cdef_tile_col[0].sb_row[i * 64 >> cur_sb128..(i + 1) * 64 >> cur_sb128], &_ctx.cdef_tile_col[0], fpre, bd);

    fs_cdef_compute_sb_row(&_ctx, i, 64 >> cur_sb128, 0);
    fs_cdef_compute_sb_row(&_ctx, i + 1, 64 >> cur_sb128, 0);

    const all_strength: [3]u8 = [3, 3, 2];
    const cdef_max_strength: u8 = 6;

    for (var i: usize = 0; i < sb_w; i += 1) {
        if (i % (32 >> cur_sb128) == 0) {
            sbo_col = sbo + i;
            if (cur_sb128 == 1) {
                dlist_row[i] = _ctx.cdef_p[sbo_col] < cdef_max_strength ? _ctx.cdef_p[sbo_col] : cdef_max_strength;
            } else if (cur_sb128 == 0 && i % (16 >> cur_sb128) == 0) {
                dlist_row[i] = _ctx.cdef_p[sbo_col] < cdef_max_strength ? _ctx.cdef_p[sbo_col] : cdef_max_strength;
            } else {
                dlist_row[i] = _ctx.cdef_p[sbo_col] < all_strength[2] ? _ctx.cdef_p[sbo_col] : all_strength[2];
            }
        }
        tlist_row[i] = dlist_row[i];
    }

    var tlist_row_0: []u16 = &_ctx.cdef_tile_col[j].sb_row[0].tlist[sbo_col * 64 >> cur_sb128..(sbo_col + 1) * 64 >> cur_sb128];

    for (var i: usize = 0; i < sb_w >> 1; i += 1) {
        if (i % (32 >> cur_sb128) == 0) {
            tlist_row_0[i] = all_strength[0];
            tlist_row_0[i + w] = all_strength[0];
        }
    }

    if (uvdec) {
        w >>= 1;
        h >>= 1;
        xdec = 1;
        ydec = 1;
    }

    for (var i: usize = 0; i < w * h; i += 1) {
        if (i % (32 >> cur_sb128) == 0) {
            let sum: f64 = 0.0;
            let j: usize = i;
            for (let jj: usize = 0; jj < 8 >> ydec; jj += 1) {
                for (let ii: usize = 0; ii < 8 >> xdec; ii += 1) {
                    let ij: usize = j + ii;
                    sum += fpre[ydec][xdec][(tlist[ij] >> 1) & 15];
                }
                j += w;
            }
            ti[0][i] = @intCast(u16, sum + 0.5);
        }
    }

    var luma_tile_x: usize = 0;
    var luma_tile_y: usize = 0;
    var tile_w: usize = 64 >> luma_sb128;
    var tile_h: usize = 64 >> luma_sb128;
    var i: usize = 0;
    var j: usize = 0;
    var offset_x: usize = 0;
    var offset_y: usize = 0;
    var srcstride: usize = 256;

    fs_cdef_sbrow_tile(&_ctx, &[_ctx.cdef_tile_col[0].sb_row[0]], &_ctx.cdef_tile_col[0], fpre, bd);

    fs_cdef_sbrow(&_ctx, fpre, bd);
    fs_cdef_sbrow_tile(&_ctx, &[_ctx.cdef_tile_col[0].sb_row[0]], &_ctx.cdef_tile_col[0], fpre, bd);

    fs_cdef_compute_sb_row(&_ctx, 0, 64 >> luma_sb128, 0);
    fs_cdef_compute_sb_row(&_ctx, 1, 64 >> luma_sb128, 0);

    const cur_sb128: u32 = 0;

    var ntile_col2: u16 = 1;
    var ntile_row2: u16 = 1;

    if (cur_sb128 != 0) {
        ntile_col2 = w / (64 >> cur_sb128);
        ntile_row2 = h / (64 >> cur_sb128);
    }

    for (var i: u16 = 0; i < ntile_col2 * ntile_row2; i += 1) {
        var luma_tile_x: usize = i % ntile_col2;
        var luma_tile_y: usize = i / ntile_col2;
        fs_cdef_sbrow_tile(&_ctx, &[_ctx.sb_row[luma_tile_y * 64 >> cur_sb128..(luma_tile_y + 1) * 64 >> cur_sb128]], &_ctx.cdef_tile_col[luma_tile_x], fpre, bd);
    }
}
