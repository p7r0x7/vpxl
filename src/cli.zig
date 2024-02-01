// SPDX-License-Identifier: MPL-2.0
// Copyright © 2023 The VPXL Contributors. All rights reserved.
// Contributors responsible for this file:
// @p7r0x7 <mattrbonnette@pm.me>

const cova = @import("cova");
const io = @import("std").io;
const os = @import("std").os;
const fs = @import("std").fs;
const mem = @import("std").mem;
const rand = @import("std").rand;
const ascii = @import("std").ascii;
const builtin = @import("builtin");

//
// The following do not exist in the binary as they appear below; they are, instead, efficiently re-expressed at COMPTIME.
//

// Comptime-only structure assemblers
fn command(cmd: []const u8, desc: []const u8, cmds: ?[]const CommandT, opts: ?[]const CommandT.OptionT) CommandT {
    const help = [_]CommandT.OptionT{
        // TODO(@p7r0x7): implement aliases now that it's supported by Cova.
        option("h", value("", bool, false, parsers.parseBool), ""),
        option("help", value("", bool, false, parsers.parseBool), "Show this help message and exit."),
    };
    return .{ .name = cmd, .description = desc, .hidden = desc.len == 0, .sub_cmds = cmds, .opts = help ++ opts.? };
}

fn option(opt: []const u8, val: CommandT.ValueT, desc: []const u8) CommandT.OptionT {
    return .{ .name = opt, .long_name = opt, .description = desc, .hidden = desc.len == 0, .val = val };
}

fn value(val: []const u8, comptime ValType: type, default: ?ValType, parse: *const fn ([]const u8, mem.Allocator) anyerror!ValType) CommandT.ValueT {
    return CommandT.ValueT.ofType(ValType, .{ .name = val, .default_val = default, .parse_fn = parse });
}

/// Comptime-assembled Cova command definition for VPXL
const vpxl_cmd: CommandT = command("vpxl",
    \\ a VP9 encoder by Matt R Bonnette
    // Band-Aid spaces
, &.{
    command("xpsnr", "Calculate XPSNR score between two or more (un)compressed inputs.", null, &.{
        option("in", value("input_path", []const u8, null, parsers.parsePathOrURL),
            \\Path from which (un)compressed frames are to be demuxed and decoded by FFmpeg for scoring.
            \\This option must be passed more than once.
        ),
    }),
    command("fssim", "Calculate FastSSIM score between two or more (un)compressed inputs.", null, &.{
        option("in", value("input_path", []const u8, null, parsers.parsePathOrURL),
            \\Path from which (un)compressed frames are to be demuxed and decoded by FFmpeg for scoring.
            \\This option must be passed more than once.
        ),
    }),
    command("pp",
        \\   Filter a(n) (un)compressed input with VPXL's opinionated, encoder- and
        \\               content-agnostic video preprocessor.
        // Band-Aid spaces
    , null, &.{
        option("in", value("input_path", []const u8, null, parsers.parsePathOrURL),
            \\Path from which (un)compressed frames are to be demuxed, decoded, and lossily filtered by
            \\FFmpeg to improve transcoding efficiency.
        ),
        //option("out", value("output_path", []const u8, null, parsers.parseOutPath),
        //   \\Path to which the filtered frames will be muxed.
        //At the cost of reduced playback compatibility, lossily preprocesses input frames for
        //improved coding efficiency: First, crops out uniform letterboxes and pillarbars within
        //consistent GOPs. Then, increases 8-bit inputs to 10-bit and denoises imperceptibly noisy
        //frames. And lastly, converts CFR inputs to VFR, dropping perceptually-duplicate frames.
    }),
}, &.{
    option("pix", value("pixel_format", []const u8, "auto", parsers.parsePixelFormat),
        \\Prior to encoding, correctly convert input frames to the given pixel format; VPXL's
        \\supported values: yuv420p yuv422p yuv440p yuv444p yuv420p10le yuv422p10le yuv440p10le
        \\yuv444p10le yuv420p12le yuv422p12le yuv440p12le yuv444p12le yuva420p yuva422p yuva440p
        \\yuva444p yuva420p10le yuva422p10le yuva440p10le yuva444p10le yuva420p12le yuva422p12le
        \\yuva440p12le yuva444p12le auto
    ),
    option("in", value("input_path", []const u8, null, parsers.parsePathOrURL),
        \\Path from which (un)compressed frames are to be demuxed and decoded by FFmpeg for encoding.
    ),
    option("out", value("output_path", []const u8, null, parsers.parsePathOrURL),
        \\Path to which VPXL-compressed and FFmpeg-muxed frames are to be written. FFmpeg will mux to
        \\the container format specified by output_path's file extension.
    ),
    option("pass", value("vpxl_pass", []const u8, "only", parsers.parsePass),
        \\VPXL encoding pass to employ: 'only' refers to the only pass of one-pass encoding. 'first'
        \\refers to the first pass of two-pass encoding. 'second' refers to the second pass of two-
        \\pass encoding.
    ),
    option("gop", value("gop_duration", []const u8, "auto", parsers.parseTime),
        \\Keyframes will be placed at intervals of the given duration or frame count. 'auto' uses a
        \\fast perceptual heuristic to detect scene changes, providing near-optimally efficient
        \\keyframe placement at convenient places for seeking from and cutting to. Given this logic,
        \\values of 0 or 0s/ms produce all-intra streams.
    ),
    option("full", value("", bool, false, parsers.parseBool),
        \\Preserve full-range when using option -pix. This will reduce playback compatibility.
    ),
    option("resume", value("", bool, true, parsers.parseBool),
        \\Allow automatic resumption of a previously-interrupted encoding; pass 'first' cannot be
        \\resumed.
    ),
    option("ansi", value("", bool, true, parsers.parseBool),
        \\Emit ANSI escape sequences with terminal output when available.
    ),
});

const usage_margin = usage_margin: {
    var max: usize = vpxl_cmd.name.len;
    for (vpxl_cmd.sub_cmds) |sub_cmd| {
        const cmdlen: usize = sub_cmd.name.len;
        if (cmdlen > max) max = cmdlen;
    }
    break :usage_margin max + colon_space.len;
};

//
// Almost all parts of the following exist in the binary and directly affect RUNTIME performance characteristics.
//

/// Cova configuration type identity
const CommandT = cova.Command.Custom(.{
    .indent_fmt = "    ",
    .global_case_sensitive = false,
    .global_sub_cmds_mandatory = false,
    .global_usage_fn = printers.commandUsage,
    .global_help_fn = printers.commandHelp,
    .opt_config = .{
        .global_usage_fn = printers.optionUsage,
        .global_help_fn = printers.optionHelp,
        .allow_abbreviated_long_opts = false,
        .allow_opt_val_no_space = true,
        .opt_val_seps = "=:",
        .short_prefix = null,
        .long_prefix = "-",
    },
    .val_config = .{
        .global_set_behavior = .Last,
        .add_base_floats = false,
        .add_base_ints = false,
        .use_slim_base = true,
        .max_children = 12,
    },
});

/// Parsing callback functions for Cova values
const parsers = struct {
    fn parseDeadline(arg: []const u8, _: mem.Allocator) ![]const u8 {
        const deadlines = [_][]const u8{ "fast", "good", "best" };
        for (deadlines) |str| if (ascii.eqlIgnoreCase(str, arg)) return str;
        return error.DeadlineValueUnsupported;
    }

    fn parsePixelFormat(arg: []const u8, _: mem.Allocator) ![]const u8 {
        const format = [_][]const u8{
            // zig fmt: off
             "yuv420p",  "yuv420p10le",  "yuv420p12le",
             "yuv422p",  "yuv422p10le",  "yuv422p12le",
             "yuv440p",  "yuv440p10le",  "yuv440p12le",
             "yuv444p",  "yuv444p10le",  "yuv444p12le",
            "yuva420p", "yuva420p10le", "yuva420p12le",
            "yuva422p", "yuva422p10le", "yuva422p12le",
            "yuva440p", "yuva440p10le", "yuva440p12le",
            "yuva444p", "yuva444p10le", "yuva444p12le", "auto",
            // zig fmt: on
        };
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

/// Printing callback functions for Cova commands and options
const printers = struct {
    fn commandUsage(root: anytype, wr: anytype, _: mem.Allocator) !void {
        _ = try wr.write("USAGE   ");
        _ = try wr.write(root.name);
        _ = try wr.write("   "); // Band-Aid spaces
        if (root.opts) |opts| {
            for (opts) |opt| {
                _ = try wr.write("[" ++ @TypeOf(opt).long_prefix.?);
                _ = try wr.write(opt.name);
                const child_type = opt.val.childType();
                if (!mem.eql(u8, child_type, "bool")) {
                    try wr.writeByte('=');
                    _ = try wr.write(child_type);
                }
                try wr.writeByte(']');
            }
        }
        _ = try wr.write(ns ++ ns);
    }

    fn commandHelp(root: anytype, wr: anytype, _: mem.Allocator) !void {
        try root.usage(wr);

        const indent = @TypeOf(root.*).indent_fmt;
        _ = try wr.write("(SUB)COMMANDS" ++ ns ++ ns ++ indent ++ indent);
        _ = try wr.write(root.name);
        _ = try wr.write(colon_space);
        if (active_scheme.one) |v| _ = try wr.write(v);
        _ = try wr.write(root.description);
        if (active_scheme.one) |_| _ = try wr.write(zero);
        _ = try wr.write(ns ++ ns);

        if (root.sub_cmds) |cmds| {
            for (cmds) |cmd| {
                if (cmd.hidden) continue;
                _ = try wr.write(indent ++ indent);
                _ = try wr.write(cmd.name);
                _ = try wr.write(colon_space);
                if (active_scheme.two) |v| _ = try wr.write(v);
                _ = try wr.write(cmd.description);
                if (active_scheme.two) |_| _ = try wr.write(zero);
                try wr.writeByte(nb);
            }
            try wr.writeByte(nb);
        }
        
        if (root.opts) |opts| {
            _ = try wr.write("OPTIONS" ++ ns ++ ns);
            for (opts) |opt| {
                if (opt.hidden) continue;
                try opt.help(wr);
                try wr.writeByte(nb);
            }
        }
    }

    fn optionUsage(opt: anytype, wr: anytype, _: mem.Allocator) !void {
        _ = try wr.write(@TypeOf(opt.*).long_prefix.?);
        _ = try wr.write(opt.long_name.?);
        try wr.writeByte(' ');

        if (active_scheme.one) |v| _ = try wr.write(v);
        try wr.writeByte('"');
        const val_name = opt.val.name();
        if (val_name.len > 0) {
            _ = try wr.write(val_name);
            try wr.writeByte(' ');
        }
        try wr.writeByte('(');
        const child_type = opt.val.childType();
        _ = try wr.write(child_type);
        _ = try wr.write(")\"");
        if (active_scheme.one) |_| _ = try wr.write(zero);

        var default_as_string: ?[]const u8 = null;
        if (mem.eql(u8, child_type, "[]const u8")) {
            default_as_string = opt.val.generic.string.default_val;
        } else if (mem.eql(u8, child_type, "bool")) {
            default_as_string = if (opt.val.generic.bool.default_val) |v| if (v) "true" else "false" else null;
        }
        if (default_as_string) |str| {
            _ = try wr.write(" default" ++ colon_space);
            _ = try wr.write(str);
        }
    }

    fn optionHelp(opt: anytype, wr: anytype, _: mem.Allocator) !void {
        _ = try wr.write(@TypeOf(opt.*).indent_fmt.?);
        try opt.usage(wr);

        var it = mem.splitScalar(u8, opt.description, nb);
        while (it.next()) |line| {
            _ = try wr.write(ns ++ @TypeOf(opt.*).indent_fmt.?);
            if (active_scheme.two) |v| _ = try wr.write(v);
            _ = try wr.write(line);
            if (active_scheme.two) |_| _ = try wr.write(zero);
        }
        try wr.writeByte(nb);
    }
};

const ns = "\n";
pub const nb = '\n';
const zero = "\x1b[0m";
const colon_space = ": ";

var active_scheme = ColorScheme{};

const schemes = [_]ColorScheme{
    // Transit          Schoolbus Yellow      Highway Sign Green
    ColorScheme{ .one = "\x1b[1;38;5;220m", .two = "\x1b[38;5;36m" },
    // Discord            Butter Yellow             Blurple
    ColorScheme{ .one = "\x1b[1;38;5;230m", .two = "\x1b[38;5;111m" },
};

const ColorScheme = struct { one: ?[]const u8 = null, two: ?[]const u8 = null };

fn configureColorScheme() !void {
    // TODO(@p7r0x7): Move this to main() if a PRNG is ever elsewhere required.
    var sfc = rand.Sfc64.init(seed: {
        var tmp: u64 = undefined;
        try os.getrandom(mem.asBytes(&tmp));
        break :seed tmp;
    });
    active_scheme = schemes[sfc.random().uintLessThan(u64, schemes.len)];
}

fn configureEscapeCodes(pipe: fs.File, it: *cova.ArgIteratorGeneric) !void {
    const flag: bool = flag: {
        defer it.reset();
        while (it.next()) |arg| {
            if (arg.len < 5) continue;
            if (ascii.eqlIgnoreCase("-ansi", arg[0..5])) {
                const val = switch (arg[5]) {
                    '=', ':', ' ' => arg[6..],
                    else => arg[5..],
                };
                const T = [_][]const u8{ "1", "true", "t", "yes", "y" };
                const F = [_][]const u8{ "0", "false", "f", "no", "n" };
                for (T) |str| if (ascii.eqlIgnoreCase(str, val)) break :flag true;
                for (F) |str| if (ascii.eqlIgnoreCase(str, val)) break :flag false;
            }
        }
        break :flag true;
    };
    const available = io.tty.detectConfig(pipe) == .escape_codes;
    if (available and flag) try configureColorScheme();
}

/// runVPXL() is the entry point for the CLI.
pub fn runVPXL(pipe: fs.File, ally: mem.Allocator) !void {
    const wr = pipe.writer();
    var buffered = io.bufferedWriter(wr);
    const bw = buffered.writer();
    defer buffered.flush() catch unreachable;

    const vpxl_cli = try vpxl_cmd.init(ally, .{ .add_help_cmds = false, .add_help_opts = false });
    defer vpxl_cli.deinit();

    var arg_it = try cova.ArgIteratorGeneric.init(ally);
    try configureEscapeCodes(pipe, &arg_it);
    cova.parseArgs(&arg_it, CommandT, &vpxl_cli, bw, .{
        .skip_exe_name_arg = true,
        .auto_handle_usage_help = false,
        .enable_opt_termination = true,
        .err_reaction = .Help,
    }) catch |err| return err;
    arg_it.deinit();

    const cmd = (&vpxl_cli).sub_cmd orelse &vpxl_cli;
    if (cmd.checkOpts(&[_][]const u8{ "h", "help" }, .{}) or !cmd.checkOpts(&[_][]const u8{"in"}, .{})) {
        try cmd.help(bw);
        try buffered.flush();
    }

    if (builtin.mode == .Debug) try cova.utils.displayCmdInfo(CommandT, &vpxl_cli, ally, bw);
}
