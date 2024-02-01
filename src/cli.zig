// SPDX-License-Identifier: MPL-2.0
// Copyright © 2023 The VPXL Contributors. All rights reserved.
// Contributors responsible for this file:
// @p7r0x7 <mattrbonnette@pm.me>

const cova = @import("cova");
const io = @import("std").io;
const os = @import("std").os;
const fs = @import("std").fs;
const mem = @import("std").mem;
//const rand = @import("std").rand;
const ascii = @import("std").ascii;
const builtin = @import("builtin");
const utf8 = @import("std").unicode;

//
// The following do not exist in the binary as they appear below; they are, instead, efficiently re-expressed at COMPTIME.
//

/// Comptime-assembled Cova command definition for VPXL
const vpxl_cmd: CommandT = command("vpxl",
    \\ a VP9 encoder by Matt R Bonnette
    // Band-Aid spaces
, &.{
    command("xpsnr", "Calculate XPSNR score between two or more (un)compressed inputs.", null, &.{
        value("input_path", []const u8, null, parsers.parsePathOrURL,
            \\Path from which (un)compressed frames are to be demuxed and decoded by FFmpeg for scoring.
            \\This option must be passed more than once.
        ),
    }, null),
    command("fssim", "Calculate FastSSIM score between two or more (un)compressed inputs.", null, &.{
        value("input_path", []const u8, null, parsers.parsePathOrURL,
            \\Path from which (un)compressed frames are to be demuxed and decoded by FFmpeg for scoring.
            \\This option must be passed more than once.
        ),
    }, null),
    command("pp",
        \\   Filter a(n) (un)compressed input with VPXL's opinionated, encoder- and
        \\               content-agnostic video preprocessor.
        // Band-Aid spaces
    , null, &.{
        value("input_path", []const u8, null, parsers.parsePathOrURL,
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
        option("preset", null, value("x264_preset", []const u8, "auto", null, ""), ""),
    }),
}, &.{
    value("input_path", []const u8, null, parsers.parsePathOrURL,
        \\Path from which (un)compressed frames are to be demuxed and decoded by FFmpeg for encoding.
    ),
    value("output_path", []const u8, null, parsers.parsePathOrURL,
        \\Path to which VPXL-compressed and FFmpeg-muxed frames are to be written. FFmpeg will mux to
        \\the container format specified by output_path's file extension.
    ),
}, &.{
    option("pix", null, value("pixel_format", []const u8, "auto", parsers.parsePixelFormat, ""),
        \\Prior to encoding, correctly convert input frames to the given pixel format; VPXL's
        \\supported values: yuv420p yuv422p yuv440p yuv444p yuv420p10le yuv422p10le yuv440p10le
        \\yuv444p10le yuv420p12le yuv422p12le yuv440p12le yuv444p12le yuva420p yuva422p yuva440p
        \\yuva444p yuva420p10le yuva422p10le yuva440p10le yuva444p10le yuva420p12le yuva422p12le
        \\yuva440p12le yuva444p12le auto
    ),
    option("pass", null, value("vpxl_pass", []const u8, "only", parsers.parsePass, ""),
        \\VPXL encoding pass to employ: 'only' refers to the only pass of one-pass encoding. 'first'
        \\refers to the first pass of two-pass encoding. 'second' refers to the second pass of two-
        \\pass encoding.
    ),
    option("gop", null, value("gop_duration", []const u8, "auto", parsers.parseTime, ""),
        \\Terminate GOPs after gop_duration if it is terminated by a unit of time (s/ms/μs/us);
        \\otherwise, terminate GOPs after gop_duration ÷ framerate. 'auto' uses a fast, perceptual
        \\heuristic to detect scene changes, providing near-optimally-efficient keyframe placement at
        \\convenient places for seeking from and cutting to. Given this logic, values of 0 or 0s both
        \\produce all-intra streams.
    ),
    option("full", null, value("", bool, false, parsers.parseBool, ""),
        \\Preserve full-range when using option -pix. This will reduce playback compatibility.
    ),
    option("resume", null, value("", bool, true, parsers.parseBool, ""),
        \\Allow automatic resumption of a previously-interrupted encoding.
    ),
    option("version", null, value("", bool, false, parsers.parseBool, ""),
        \\Print version information string and exit.
    ),
});

// Comptime-only structure assemblers
fn command(cmd: []const u8, desc: []const u8, cmds: ?[]const CommandT, vals: ?[]const CommandT.ValueT, opts: ?[]const CommandT.OptionT) CommandT {
    const pre = &[_]CommandT.OptionT{
        option("help", &[_][]const u8{ "-help", "h" }, value("", bool, false, parsers.parseBool, ""),
            \\Print command help message and exit.
        ),
    };
    const post = &[_]CommandT.OptionT{
        option("ffmpeg", null, value("executable_path", []const u8, "auto", parsers.parsePathOrURL, ""),
            \\Path to FFmpeg executable. If set to 'auto', the first 'ffmpeg' found in PATH will be used.
        ),
        option("hwdec", null, value("", bool, true, parsers.parseBool, ""),
            \\Allow automatic utilization of available hardware decoding devices.
        ),
        option("verbose", &[_][]const u8{"v"}, value("", bool, false, parsers.parseBool, ""),
            \\Increment command verbosity.
        ),
        option("quiet", &[_][]const u8{"q"}, value("", bool, false, parsers.parseBool, ""),
            \\Decrement command verbosity.
        ),
        option("ansi", null, value("", bool, true, parsers.parseBool, ""),
            \\Emit ANSI escape sequences with terminal output when available.
        ),
    };
    return .{ .name = cmd, .vals = vals, .sub_cmds = cmds, .description = desc, .hidden = desc.len == 0, .opts = pre ++ (opts orelse &[_]CommandT.OptionT{}) ++ post };
}

fn option(opt: []const u8, aliases: ?[]const []const u8, val: CommandT.ValueT, desc: []const u8) CommandT.OptionT {
    return .{ .val = val, .name = opt, .long_name = opt, .description = desc, .hidden = desc.len == 0, .alias_long_names = aliases };
}

fn value(val: []const u8, comptime ValType: type, default: ?ValType, parse: ?*const fn ([]const u8, mem.Allocator) anyerror!ValType, desc: []const u8) CommandT.ValueT {
    return CommandT.ValueT.ofType(ValType, .{ .name = val, .parse_fn = parse, .default_val = default, .description = desc });
}

//
// Almost all parts of the following exist in the binary and directly affect RUNTIME performance characteristics.
//

/// Cova configuration type identity
const CommandT = cova.Command.Custom(.{
    .cmd_alias_fmt = "",
    .help_header_fmt = "",
    .subcmd_alias_fmt = "",
    .subcmds_help_fmt = "",
    .subcmds_usage_fmt = "",
    .subcmds_help_title_fmt = "",
    .vals_help_title_fmt = "",
    .opts_help_title_fmt = "",
    .usage_header_fmt = "",
    .group_title_fmt = "",
    .group_sep_fmt = "",

    .indent_fmt = "    ",
    .global_help_prefix = "",
    .global_case_sensitive = false,
    .global_vals_mandatory = false,
    .global_sub_cmds_mandatory = false,
    .global_usage_fn = printers.commandUsage,
    .global_help_fn = printers.commandHelp,
    .opt_config = .{
        .help_fmt = "",
        .usage_fmt = "",
        .global_usage_fn = printers.optionUsage,
        .global_help_fn = printers.optionHelp,
        .allow_abbreviated_long_opts = false,
        .allow_opt_val_no_space = true,
        .opt_val_seps = "=:",
        .short_prefix = null,
        .long_prefix = "-",
    },
    .val_config = .{
        .help_fmt = "",
        .usage_fmt = "",
        .global_usage_fn = printers.valueUsage,
        .global_help_fn = printers.valueHelp,
        .global_set_behavior = .Last,
        .add_base_floats = false,
        .add_base_ints = false,
        .use_slim_base = true,
        .max_children = 1,
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
    // TODO(@p7r0x7): Compare this implementation against building a io.Writer wrapper and using standard print() calls.
    fn RuneCountingPrinter(comptime Writer: type) type {
        return struct {
            writer: Writer,
            rune_count: usize = 0,

            fn print(p: *@This(), strs: anytype) !void {
                inline for (strs) |str| {
                    switch (@typeInfo(@TypeOf(str))) {
                        .Int => try p.printByte(str),
                        .Pointer => try p.printStr(str),
                        .ComptimeInt => try p.printByte(str),
                        else => @compileError("Expected byte or string, got " ++ @typeName(@TypeOf(str))),
                    }
                }
            }
            fn printStr(p: *@This(), str: []const u8) !void {
                try p.writer.writeAll(str);
                p.rune_count += try utf8.utf8CountCodepoints(str);
            }
            fn printByte(p: *@This(), byte: u8) !void {
                try p.writer.writeByte(byte);
                p.rune_count += 1;
            }
        };
    }
    fn printer(writer: anytype) RuneCountingPrinter(@TypeOf(writer)) {
        return .{ .writer = writer };
    }

    fn commandUsage(root: anytype, wr: anytype, _: mem.Allocator) !void {
        var p = printer(wr);
        try p.print(.{ ns ++ "USAGE   ", root.name, "   " }); // Band-Aid spaces
        if (root.opts) |opts| {
            for (opts) |opt| {
                try p.print(.{ "[" ++ @TypeOf(opt).long_prefix.?, opt.name });
                const child_type = opt.val.childType();
                if (!mem.eql(u8, child_type, "bool")) {
                    if (mem.eql(u8, child_type, "[]const u8")) {
                        try p.print(.{"=string"});
                    } else {
                        try p.print(.{ "=", child_type });
                    }
                }
                try p.print(.{']'});
            }
        }
        const indent = @TypeOf(root.*).indent_fmt;
        try p.print(.{ns ++ ns ++ indent ++ indent});
        if (active_scheme.one) |v| try wr.writeAll(v);
        try p.print(.{root.description});
        if (active_scheme.one) |_| try wr.writeAll(zero);
        try p.print(.{ns ++ ns});
        // return p.rune_count;
    }

    fn commandHelp(root: anytype, wr: anytype, _: mem.Allocator) !void {
        var p = printer(wr);
        try root.usage(wr);
        if (root.sub_cmds) |cmds| {
            const indent = @TypeOf(root.*).indent_fmt;
            for (cmds) |cmd| {
                if (cmd.hidden) continue;
                try p.print(.{ indent ++ indent, root.name, ' ', cmd.name, colon_space });
                if (active_scheme.two) |v| try wr.writeAll(v);
                try p.print(.{cmd.description});
                if (active_scheme.two) |_| try wr.writeAll(zero);
                try p.print(.{nb});
            }
            try p.print(.{nb});
        }
        if (root.vals) |vals| {
            try p.print(.{"VALUES" ++ ns ++ ns});
            for (vals) |val| {
                try val.help(wr);
                try p.print(.{nb});
            }
        }
        if (root.opts) |opts| {
            try p.print(.{"OPTIONS" ++ ns ++ ns});
            for (opts) |opt| {
                if (opt.hidden) continue;
                try opt.help(wr);
                try p.print(.{nb});
            }
        }
        try p.print(.{nb});
        // return p.rune_count;
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
        var p = printer(wr);
        try p.print(.{ @TypeOf(opt.*).long_prefix.?, opt.long_name.? });
        if (opt.alias_long_names) |alias_long_names| {
            for (alias_long_names) |alias_long_name| {
                try p.print(.{ ", " ++ @TypeOf(opt.*).long_prefix.?, alias_long_name });
            }
        }
        try p.print(.{' '});

        if (active_scheme.one) |v| try wr.writeAll(v);
        try p.print(.{'"'});
        const val_name = opt.val.name();
        if (val_name.len > 0) try p.print(.{ val_name, ' ' });
        try p.print(.{'('});
        const child_type = opt.val.childType();
        if (mem.eql(u8, child_type, "[]const u8")) try p.print(.{"string"}) else try wr.writeAll(child_type);
        try p.print(.{")\""});
        if (active_scheme.one) |_| try wr.writeAll(zero);

        var default_as_string: ?[]const u8 = null;
        if (mem.eql(u8, child_type, "[]const u8")) {
            default_as_string = opt.val.generic.string.default_val;
        } else if (mem.eql(u8, child_type, "bool")) {
            default_as_string = if (opt.val.generic.bool.default_val) |v| if (v) "true" else "false" else null;
        }
        if (default_as_string) |str| try p.print(.{ " default" ++ colon_space, str });
        // return p.rune_count;
    }

    fn optionHelp(opt: anytype, wr: anytype, _: mem.Allocator) !void {
        var p = printer(wr);
        try p.print(.{@TypeOf(opt.*).indent_fmt.?});
        try opt.usage(wr);

        var it = mem.splitScalar(u8, opt.description, nb);
        while (it.next()) |line| {
            try p.print(.{ns ++ @TypeOf(opt.*).indent_fmt.?});
            if (active_scheme.two) |v| try wr.writeAll(v);
            try p.print(.{line});
            if (active_scheme.two) |_| try wr.writeAll(zero);
        }
        try p.print(.{nb});
        // return p.rune_count;
    }
};

const ns = "\n";
pub const nb = '\n';
const zero = "\x1b[0m";
const colon_space = ": ";

var active_scheme = ColorScheme{};

const schemes = [_]ColorScheme{
    ColorScheme{ .one = "\x1b[40;1;38;5;230m", .two = "\x1b[38;5;111m" }, // discord: buttercream, blurple
    //ColorScheme{ .one = "\x1b[40;1;38;5;220m", .two = "\x1b[38;5;36m" }, // transit: schoolbus yellow, highway sign green
};

const ColorScheme = struct { one: ?[]const u8 = null, two: ?[]const u8 = null };

//fn configureColorScheme() !void {
//    // TODO(@p7r0x7): Move this to main() if a PRNG is ever elsewhere required.
//    var sfc = rand.Sfc64.init(seed: {
//        var tmp: u64 = undefined;
//        try os.getrandom(mem.asBytes(&tmp));
//        break :seed tmp;
//    });
//    active_scheme = schemes[sfc.random().uintLessThan(u64, schemes.len)];
//}

fn configureEscapeCodes(pipe: fs.File, it: *cova.ArgIteratorGeneric, ally: mem.Allocator) !void {
    const flag: bool = flag: {
        defer it.reset();
        _ = it.next(); // Skip arg[0], the program name.
        while (it.next()) |arg| {
            if (arg.len < 5) continue;
            if (ascii.eqlIgnoreCase("-ansi", arg[0..5])) {
                const val = switch (arg[5]) {'=', ':', ' ' => arg[6..], else => arg[5..]};
                break :flag try parsers.parseBool(val, ally);
            }
        }
        break :flag true;
    };
    const available = io.tty.detectConfig(pipe) == .escape_codes;
    if (available and flag) active_scheme = schemes[0];
}

/// runVPXL() is the entry point for the CLI.
pub fn runVPXL(pipe: fs.File, ally: mem.Allocator) !void {
    const wr = pipe.writer();
    var bfwr = io.bufferedWriter(wr);
    const bw = bfwr.writer();
    defer bfwr.flush() catch @panic("Failed to flush buffered writer.");

    const vpxl_cli = try vpxl_cmd.init(ally, .{ .add_help_cmds = false, .add_help_opts = false });
    defer vpxl_cli.deinit();

    var arg_it = try cova.ArgIteratorGeneric.init(ally);
    try configureEscapeCodes(pipe, &arg_it, ally);
    cova.parseArgs(&arg_it, CommandT, vpxl_cli, bw, .{
        .auto_handle_usage_help = false,
        .enable_opt_termination = true,
        .skip_exe_name_arg = true,
        .err_reaction = .Help,
    }) catch |err| return err;
    (&arg_it).deinit();

    const cmd = vpxl_cli.sub_cmd orelse vpxl_cli;
    var mlem = try cmd.getVals(.{});
    const z = mlem.get("input_path");
    if (cmd.checkOpts(&[_][]const u8{"help"}, .{}) or !z.?.generic.string.is_set) {
        try cmd.help(bw);
        try bfwr.flush();
    }

    if (builtin.mode == .Debug) try cova.utils.displayCmdInfo(CommandT, vpxl_cli, ally, bw);
}
