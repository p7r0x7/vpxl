// SPDX-License-Identifier: MPL-2.0
// Copyright © 2024 The VPXL Contributors. All rights reserved.
// Contributors responsible for this file:
// @p7r0x7 <mattrbonnette@pm.me>

const cova = @import("cova");
const io = @import("std").io;
const os = @import("std").os;
const fs = @import("std").fs;
const mem = @import("std").mem;
const db = @import("std").debug;
const ascii = @import("std").ascii;
const builtin = @import("builtin");
const utf8 = @import("std").unicode;

//
// The following do not exist in the binary as they appear below; they are, instead, efficiently re-expressed at COMPTIME.
//

/// Cova configuration type identity
const VPXLCmd = cmd: {
    var cmd_config = cova.Command.Config.noFormats();

    cmd_config.opt_config.global_usage_fn = printing.optionUsage;
    cmd_config.opt_config.global_help_fn = printing.optionHelp;
    cmd_config.opt_config.allow_abbreviated_long_opts = false;
    cmd_config.opt_config.allow_opt_val_no_space = true;
    cmd_config.opt_config.indent_fmt = spaces[0..4];
    cmd_config.opt_config.allow_arg_indices = false;
    cmd_config.opt_config.opt_val_seps = "=:";
    cmd_config.opt_config.short_prefix = null;
    cmd_config.opt_config.long_prefix = "-";

    cmd_config.val_config.global_usage_fn = printing.valueUsage;
    cmd_config.val_config.global_help_fn = printing.valueHelp;
    cmd_config.val_config.use_custom_bit_width_range = false;
    cmd_config.val_config.global_set_behavior = .Last;
    cmd_config.val_config.indent_fmt = spaces[0..4];
    cmd_config.val_config.allow_arg_indices = false;
    cmd_config.val_config.add_base_floats = false;
    cmd_config.val_config.add_base_ints = false;
    cmd_config.val_config.use_slim_base = true;
    cmd_config.val_config.max_children = 1;

    cmd_config.global_usage_fn = printing.commandUsage;
    cmd_config.global_help_fn = printing.commandHelp;
    cmd_config.global_allow_inheritable_opts = true;
    cmd_config.global_sub_cmds_mandatory = false;
    cmd_config.global_case_sensitive = false;
    cmd_config.global_vals_mandatory = false;
    cmd_config.indent_fmt = spaces[0..4];
    cmd_config.allow_arg_indices = false;
    cmd_config.global_help_prefix = "";

    break :cmd cova.Command.Custom(cmd_config);
};

/// Comptime-assembled Cova command definition for VPXL
const vpxl_cmd: VPXLCmd = command("vpxl",
    \\Encode a(n) (un)compressed input with the VPXL VP9 video encoder, courtesy of Matt R Bonnette (@p7r0x7) et al.
, &.{
    command("xpsnr",
        \\Calculate XPSNR score between two or more (un)compressed inputs.
    , null, &.{
        value("input_path", []const u8, null, parsing.parsePathOrURL,
            \\Path from which (un)compressed frames are to be demuxed and decoded by FFmpeg for scoring.
            \\This option must be passed more than once.
        ),
    }, null),
    command("fssim",
        \\Calculate FastSSIM score between two or more (un)compressed inputs.
    , null, &.{
        value("input_path", []const u8, null, parsing.parsePathOrURL,
            \\Path from which (un)compressed frames are to be demuxed and decoded by FFmpeg for scoring.
            \\This option must be passed more than once.
        ),
    }, null),
    command("pp",
        \\Filter a(n) (un)compressed input with VPXL's opinionated, encoder- and content-agnostic video preprocessor.
    , null, &.{
        value("input_path", []const u8, null, parsing.parsePathOrURL,
            \\Path from which (un)compressed frames are to be demuxed, decoded, and lossily filtered by
            \\FFmpeg to improve transcoding efficiency.
        ),
        //option("out", value("output_path", []const u8, null, parsers.parseOutPath),
        //   \\Path to which the filtered frames will be muxed.
        //At the cost of reduced playback compatibility, lossily preprocesses input frames for
        //improved coding efficiency: First, crops out uniform letterboxes and pillarbars within
        //consistent GOPs. Then, increases 8-bit inputs to 10-bit and denoises imperceptibly noisy
        //frames. And lastly, converts CFR inputs to VFR, dropping perceptually-duplicate frames.
    }, &.{
        option("preset", null, false, value("x264_preset", []const u8, "auto", null, ""), ""),
    }),
}, &.{
    value("input_path", []const u8, null, parsing.parsePathOrURL,
        \\Path from which (un)compressed frames are to be demuxed and decoded by FFmpeg for encoding.
    ),
    value("output_path", []const u8, null, parsing.parsePathOrURL,
        \\Path to which VPXL-compressed and FFmpeg-muxed frames are to be written. FFmpeg will mux to
        \\the container format specified by output_path's file extension.
    ),
}, &.{
    option("pix", null, false, value("pixel_format", []const u8, "auto", parsing.parsePixelFormat, ""),
        \\Prior to encoding, correctly convert input frames to the given pixel format; VPXL's
        \\supported values: yuv420p yuv422p yuv440p yuv444p yuv420p10le yuv422p10le yuv440p10le
        \\yuv444p10le yuv420p12le yuv422p12le yuv440p12le yuv444p12le yuva420p yuva422p yuva440p
        \\yuva444p yuva420p10le yuva422p10le yuva440p10le yuva444p10le yuva420p12le yuva422p12le
        \\yuva440p12le yuva444p12le auto
    ),
    option("pass", null, false, value("vpxl_pass", []const u8, "only", parsing.parsePass, ""),
        \\VPXL encoding pass to employ: 'only' refers to the only pass of one-pass encoding. 'first'
        \\refers to the first pass of two-pass encoding. 'second' refers to the second pass of two-
        \\pass encoding.
    ),
    option("gop", null, false, value("gop_duration", []const u8, "auto", parsing.parseTime, ""),
        \\Terminate GOPs after gop_duration if it is terminated by a unit of time (s/ms/μs/us);
        \\otherwise, terminate GOPs after gop_duration ÷ framerate. 'auto' uses a fast, perceptual
        \\heuristic to detect scene changes, providing near-optimally-efficient keyframe placement at
        \\convenient places for seeking from and cutting to. Given this logic, values of 0 or 0s both
        \\produce all-intra streams.
    ),
    option("full", null, false, value("", bool, false, parsing.parseBool, ""),
        \\Preserve full-range when using option -pix. This will reduce playback compatibility.
    ),
    option("resume", null, false, value("", bool, true, parsing.parseBool, ""),
        \\Allow automatic resumption of a previously-interrupted encoding.
    ),
    option("version", null, false, value("", bool, false, parsing.parseBool, ""),
        \\Print version information string and exit.
    ),

    option("help", &[_][]const u8{ "-help", "h" }, true, value("", bool, false, parsing.parseBool, ""),
        \\Print command help message and exit.
    ),
    option("ffmpeg", null, true, value("executable_path", []const u8, "auto", parsing.parsePathOrURL, ""),
        \\Path to FFmpeg executable. If set to 'auto', the first 'ffmpeg' found in PATH will be used.
    ),
    option("hwdec", null, true, value("", bool, true, parsing.parseBool, ""),
        \\Allow automatic utilization of hardware decoding devices available to FFmpeg.
    ),
    option("verbose", &[_][]const u8{"v"}, true, value("", bool, false, parsing.parseBool, ""),
        \\Increment command verbosity.
    ),
    option("quiet", &[_][]const u8{"q"}, true, value("", bool, false, parsing.parseBool, ""),
        \\Decrement command verbosity.
    ),
    option("ansi", null, true, value("", bool, true, parsing.parseBool, ""),
        \\Emit ANSI escape sequences with terminal output when available.
    ),
});

// Comptime-only structure assemblers
fn command(cmd: []const u8, desc: []const u8, cmds: ?[]const VPXLCmd, vals: ?[]const VPXLCmd.ValueT, opts: ?[]const VPXLCmd.OptionT) VPXLCmd {
    return .{ .name = cmd, .vals = vals, .sub_cmds = cmds, .description = replaceNewlines(desc), .hidden = desc.len == 0, .opts = opts, .allow_inheritable_opts = true };
}

fn option(opt: []const u8, aliases: ?[]const []const u8, inherit: bool, val: VPXLCmd.ValueT, desc: []const u8) VPXLCmd.OptionT {
    return .{ .val = val, .name = opt, .long_name = opt, .description = replaceNewlines(desc), .hidden = desc.len == 0, .alias_long_names = aliases, .inheritable = inherit };
}

fn value(val: []const u8, comptime ValType: type, default: ?ValType, parse: ?*const fn ([]const u8, mem.Allocator) anyerror!ValType, desc: []const u8) VPXLCmd.ValueT {
    return VPXLCmd.ValueT.ofType(ValType, .{ .name = val, .parse_fn = parse, .default_val = default, .description = replaceNewlines(desc) });
}

/// For readability, some literal strings in this file require comptime transformation before being manipulated at runtime.
inline fn replaceNewlines(comptime str: []const u8) []const u8 {
    comptime {
        @setEvalBranchQuota(3 << 10);
        var buf = str[0..].*;
        mem.replaceScalar(u8, &buf, nb, spaces[0]);
        return &buf;
    }
}

//
// Almost all parts of the following exist in the binary and directly affect RUNTIME performance characteristics.
//

/// Printing callback functions for Cova commands and options
const printing = struct {
    const schemes = [_]ColorScheme{
        ColorScheme{ .one = "\x1b[40;1;38;5;230m", .two = "\x1b[38;5;111m" }, // discord: buttercream, blurple
        //ColorScheme{ .one = "\x1b[40;1;38;5;220m", .two = "\x1b[38;5;36m" }, // transit: schoolbus yellow, highway sign green
    };
    const ColorScheme = struct { one: []const u8, two: []const u8 };
    var active_scheme: ?ColorScheme = null; // Global runtime variable.

    fn NonCSIRuneCountingWriter(comptime Wrapped: type) type {
        return struct {
            inner: Wrapped,
            rune_count: usize = 0,

            pub const Inner = Wrapped;
            pub const Error = Wrapped.Error || error{
                MalformedControlSequence,
                Utf8ExpectedContinuation,
                Utf8EncodesSurrogateHalf,
                Utf8CodepointTooLarge,
                Utf8InvalidStartByte,
                Utf8OverlongEncoding,
                TruncatedInput,
            };

            pub fn writer(rcw: *@This()) io.Writer(*@This(), Error, write) {
                return .{ .context = rcw };
            }
            fn write(rcw: *@This(), str: []const u8) !usize {
                const runes = try countVisibleRunes(str);
                defer rcw.rune_count += runes;
                try rcw.inner.writeAll(str);
                return str.len;
            }
            fn countVisibleRunes(str: []const u8) !usize {
                // https://www.wikiwand.com/en/ANSI_escape_code#CSI_(Control_Sequence_Introducer)_sequences
                const csi = "\x1b[";
                var runes: usize = 0;
                var index: usize = 0;
                while (mem.indexOfPos(u8, str, index, csi)) |start| {
                    const end = for (str[start + csi.len ..], start + csi.len..) |c, i| {
                        if (c >= '@' and c <= '~') break i;
                    } else return error.MalformedControlSequence;
                    if (start != 0) runes += try utf8.utf8CountCodepoints(str[index .. start - 1]);
                    index = end + 1;
                } else runes += try utf8.utf8CountCodepoints(str[index..]);
                return runes;
            }
        };
    }
    inline fn nonCSIRuneCountingWriter(writer: anytype) NonCSIRuneCountingWriter(@TypeOf(writer)) {
        return .{ .inner = writer };
    }

    fn SplitPattern(comptime T: type) type {
        return struct { cut_offset: isize, pattern: T };
    }
    const CharacterGroupIterator = CustomSplitIterator(u8, &[_]SplitPattern(u8){
        .{ .cut_offset = 1, .pattern = '-' },
        .{ .cut_offset = 0, .pattern = spaces[0] },
    });
    fn CustomSplitIterator(comptime T: type, comptime patterns: []const SplitPattern(T)) type {
        return struct {
            buf: []const T,
            dex: usize = 0,

            const items = items: {
                var arr: [patterns.len]T = undefined;
                for (&arr, patterns) |*i, v| i.* = v.pattern;
                break :items arr[0..];
            };
            const offsets = offsets: {
                var arr: [patterns.len]isize = undefined;
                for (&arr, patterns) |*o, v| o.* = v.cut_offset;
                break :offsets arr[0..];
            };

            pub inline fn first(csit: *@This()) []const T {
                db.assert(csit.dex == 0);
                return csit.next().?;
            }
            pub fn next(csit: *@This()) ?[]const T {
                if (csit.dex == csit.buf.len) return null;
                if (mem.indexOfAnyPos(T, csit.buf, csit.dex + 1, items)) |pos| {
                    const offset = offsets[mem.indexOfScalar(T, items, csit.buf[pos]).?];
                    const end: usize = @intCast(@as(isize, @intCast(pos)) + offset);
                    defer csit.dex += end - csit.dex;
                    return csit.buf[csit.dex..end];
                } else {
                    defer csit.dex = csit.buf.len;
                    return csit.buf[csit.dex..];
                }
            }
        };
    }

    inline fn print(wr: anytype, strs: anytype) !void {
        inline for (strs) |str| {
            switch (@typeInfo(@TypeOf(str))) {
                .Pointer => try wr.writeAll(str),
                .Int, .ComptimeInt => try wr.writeByte(str),
                else => @compileError("Expected byte or string, got " ++ @typeName(@TypeOf(str))),
            }
        }
    }

    fn commandUsage(root: anytype, wr: anytype, _: mem.Allocator) !void {
        try print(wr, .{ "USAGE   ", root.name, spaces[0] });
        if (root.sub_cmds != null) try print(wr, " [command]");
        if (root.vals) |vals| for (vals) |val| try print(wr, .{ " <", val.name(), '>' });
        if (root.opts != null) try print(wr, .{" [option ...]"});

        const indent = @TypeOf(root.*).indent_fmt;
        try print(wr, .{ns ++ ns ++ indent ++ indent});

        var rcw = nonCSIRuneCountingWriter(wr);
        var it = CharacterGroupIterator{ .buf = root.description };
        var next: ?[]const u8 = it.first();
        while (next != null) : (next = it.next()) {
            if (rcw.rune_count + next.?.len <= margin) {
                try print(rcw.writer(), .{next.?});
            } else {
                rcw.rune_count = 0;
                if (printing.active_scheme) |_| try print(wr, .{zero});
                try print(wr, .{ns ++ indent});
                if (printing.active_scheme) |v| try print(wr, .{v.one});
                try print(rcw.writer(), .{if (next.?[0] == spaces[0]) next.?[1..] else next.?});
            }
        }
        if (printing.active_scheme) |_| try print(wr, .{zero});
        try print(wr, .{ns});
    }

    fn commandHelp(root: anytype, wr: anytype, _: mem.Allocator) !void {
        try root.usage(wr);
        if (root.sub_cmds) |cmds| {
            const indent = @TypeOf(root.*).indent_fmt;
            for (cmds) |cmd| {
                if (cmd.hidden) continue;
                try print(wr, .{ indent ++ indent, root.name, spaces[0], cmd.name, ":  " });
                if (printing.active_scheme) |v| try print(wr, .{v.one});
                try print(wr, .{cmd.description});
                if (printing.active_scheme) |_| try print(wr, .{zero});
                try print(wr, .{nb});
            }
            try print(wr, .{nb});
        }
        if (root.vals) |vals| {
            try print(wr, .{ spaces[0..89], ":values" ++ ns ++ ns });
            for (vals) |val| {
                try val.help(wr);
                try print(wr, .{nb});
            }
        }
        if (root.opts) |opts| {
            try print(wr, .{ spaces[0..88], ":options" ++ ns ++ ns });
            for (opts) |opt| {
                if (opt.hidden) continue;
                if (opt.inheritable) continue;
                try opt.help(wr);
                try print(wr, .{nb});
            }
            try print(wr, .{ ns ++ "GLOBAL", spaces[0..82], ":options" ++ ns ++ ns });
            for (opts) |opt| {
                if (opt.hidden) continue;
                if (!opt.inheritable) continue;
                try opt.help(wr);
                try print(wr, .{nb});
            }
        }
    }

    fn valueUsage(val: anytype, wr: anytype, _: mem.Allocator) !void {
        _ = val; // autofix
        _ = wr; // autofix
    }

    fn valueHelp(val: anytype, wr: anytype, _: mem.Allocator) !void {
        _ = val; // autofix
        _ = wr; // autofix
    }

    fn optionUsage(opt: anytype, wr: anytype, _: mem.Allocator) !void {
        try print(wr, .{ @TypeOf(opt.*).long_prefix.?, opt.long_name.? });
        if (opt.alias_long_names) |alias_long_names| {
            for (alias_long_names) |alias_long_name| {
                try print(wr, .{ ", " ++ @TypeOf(opt.*).long_prefix.?, alias_long_name });
            }
        }
        try print(wr, .{spaces[0]});

        if (printing.active_scheme) |v| try print(wr, .{v.one});
        try print(wr, .{'"'});
        const val_name = opt.val.name();
        if (val_name.len > 0) try print(wr, .{ val_name, spaces[0] });
        try print(wr, .{'('});
        const child_type = opt.val.childType();
        if (mem.eql(u8, child_type, "[]const u8")) try print(wr, .{"string"}) else try print(wr, .{child_type});
        try print(wr, .{")\""});
        if (printing.active_scheme) |_| try print(wr, .{zero});

        var default_as_string: ?[]const u8 = null;
        if (mem.eql(u8, child_type, "[]const u8")) {
            default_as_string = opt.val.generic.string.default_val;
        } else if (mem.eql(u8, child_type, "bool")) {
            default_as_string = if (opt.val.generic.bool.default_val) |v| if (v) "true" else "false" else return;
        }
        if (default_as_string) |str| try print(wr, .{ " default: ", str });
    }

    fn optionHelp(opt: anytype, wr: anytype, _: mem.Allocator) !void {
        try print(wr, .{@TypeOf(opt.*).indent_fmt.?});
        var rcw = nonCSIRuneCountingWriter(wr);
        try opt.usage(rcw.writer());

        try print(rcw.writer(), .{spaces[0..2]});
        if (printing.active_scheme) |v| try print(wr, .{v.two});
        var it = CharacterGroupIterator{ .buf = opt.description };
        var next: ?[]const u8 = it.first();
        while (next != null) : (next = it.next()) {
            if (rcw.rune_count + next.?.len <= margin) {
                try print(rcw.writer(), .{next.?});
            } else {
                rcw.rune_count = 0;
                if (printing.active_scheme) |_| try print(wr, .{zero});
                try print(wr, .{ns ++ @TypeOf(opt.*).indent_fmt.?});
                if (printing.active_scheme) |v| try print(wr, .{v.two});
                try print(rcw.writer(), .{if (next.?[0] == spaces[0]) next.?[1..] else next.?});
            }
        }
        if (printing.active_scheme) |_| try print(wr, .{zero});
        try print(wr, .{ns});
    }

    fn isCSISupported(pipe: fs.File, it: *cova.ArgIteratorGeneric, ally: mem.Allocator) !bool {
        const available = io.tty.detectConfig(pipe) == .escape_codes;
        if (available) {
            return flag: {
                defer it.reset();
                _ = it.next(); // Skip arg[0], the program name.
                while (it.next()) |arg| {
                    if (arg.len < 5) continue;
                    if (ascii.eqlIgnoreCase("-ansi", arg[0..5])) {
                        const seps = VPXLCmd.OptionT.opt_val_seps;
                        const val = switch (arg[5]) {
                            seps[0], seps[1], spaces[0] => arg[6..],
                            else => arg[5..],
                        };
                        break :flag parsing.parseBool(val, ally);
                    }
                }
                break :flag true;
            };
        } else return false;
    }
};
const margin = columns - (VPXLCmd.indent_fmt.len * 2);
const spaces = [_]u8{' '} ** 89; // Adjust as necessary.
const zero = "\x1b[0m";
const columns = 100;
const ns = "\n";
const nb = '\n';

/// runVPXL() is the entry point for the CLI.
pub fn runVPXL(pipe: fs.File, ally: mem.Allocator) !void {
    var bfwr = io.bufferedWriter(pipe.writer());
    defer bfwr.flush() catch db.panic("{s}", .{"Failed to flush buffered writer to pipe."});
    try printing.print(bfwr.writer(), .{nb});
    defer printing.print(pipe.writer(), .{nb}) catch db.panic("{s}", .{"Couldn't print final newline."});

    const vpxl_cli = try vpxl_cmd.init(ally, .{
        .add_cmd_help_group = .DoNotAdd,
        .add_opt_help_group = .DoNotAdd,
        .add_help_cmds = false,
        .add_help_opts = false,
    });
    defer vpxl_cli.deinit();
    defer if (builtin.mode == .Debug) cova.utils.displayCmdInfo(VPXLCmd, vpxl_cli, ally, bfwr.writer()) catch
        db.panic("{s}", .{"Failed to display Cova debug info."});
    {
        var arg_it = try cova.ArgIteratorGeneric.init(ally);
        printing.active_scheme = if (try printing.isCSISupported(pipe, &arg_it, ally)) printing.schemes[0] else null;
        try cova.parseArgs(&arg_it, VPXLCmd, vpxl_cli, bfwr.writer(), .{
            .set_opt_termination_symbol = "--", // This is the most common terminator, even if long flags start with '-'.
            .auto_handle_usage_help = false,
            .enable_opt_termination = true,
            .skip_exe_name_arg = true,
            .err_reaction = .Help,
        });
        (&arg_it).deinit();
    }
    {
        const cmd = vpxl_cli.sub_cmd orelse {
            try vpxl_cli.help(bfwr.writer());
            try bfwr.flush();
            return;
        };
        var mlem = try cmd.getVals(.{});
        const z = mlem.get("input_path");
        if (cmd.checkOpts(&[_][]const u8{"help"}, .{}) or !z.?.generic.string.is_set) {
            try cmd.help(bfwr.writer());
            try bfwr.flush();
        }
    }
}

/// Parsing callback functions for Cova values
const parsing = struct {
    fn parseDeadline(arg: []const u8, _: mem.Allocator) ![]const u8 {
        const deadlines = [_][]const u8{ "fast", "good", "best" };
        for (deadlines) |str| if (ascii.eqlIgnoreCase(str, arg)) return str;
        return error.DeadlineValueUnsupported;
    }

    fn parsePixelFormat(arg: []const u8, _: mem.Allocator) ![]const u8 {
        // zig fmt: off
        const format = [_][]const u8{
             "yuv420p",  "yuv420p10le",  "yuv420p12le",
             "yuv422p",  "yuv422p10le",  "yuv422p12le",
             "yuv440p",  "yuv440p10le",  "yuv440p12le",
             "yuv444p",  "yuv444p10le",  "yuv444p12le",
            "yuva420p", "yuva420p10le", "yuva420p12le",
            "yuva422p", "yuva422p10le", "yuva422p12le",
            "yuva440p", "yuva440p10le", "yuva440p12le",
            "yuva444p", "yuva444p10le", "yuva444p12le", "auto",
        };
        // zig fmt: on
        for (format) |str| if (ascii.eqlIgnoreCase(str, arg)) return str;
        return error.PixelFormatUnsupportedByVPXL;
    }

    fn parsePathOrURL(arg: []const u8, _: mem.Allocator) ![]const u8 {
        return arg;
    }

    fn parsePass(arg: []const u8, _: mem.Allocator) ![]const u8 {
        const passes = [_][]const u8{ "only", "first", "second" };
        for (passes) |str| if (ascii.eqlIgnoreCase(str, arg)) return str;
        return error.PassValueUnsupported;
    }

    fn parseTime(arg: []const u8, _: mem.Allocator) ![]const u8 {
        _ = arg;
        return error.TimeValueUnsupported;
    }

    fn parseBool(arg: []const u8, _: mem.Allocator) !bool {
        const T = [_][]const u8{ "1", "true", "t", "yes", "y" };
        const F = [_][]const u8{ "0", "false", "f", "no", "n" };
        for (T) |str| if (ascii.eqlIgnoreCase(str, arg)) return true;
        for (F) |str| if (ascii.eqlIgnoreCase(str, arg)) return false;
        return error.BooleanValueUnsupported;
    }
};
