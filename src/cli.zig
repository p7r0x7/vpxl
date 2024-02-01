const cova = @import("cova");
const io = @import("std").io;
const os = @import("std").os;
const fs = @import("std").fs;
const mem = @import("std").mem;
const rand = @import("std").rand;
const time = @import("std").time;
const ascii = @import("std").ascii;
const builtin = @import("builtin");

/// Cova configuration type identity
pub const CommandT = cova.Command.Custom(.{
    .global_usage_fn = struct {
        fn usage(root: anytype, wr: anytype, _: mem.Allocator) !void {
            _ = try wr.write("USAGE   ");
            _ = try wr.write(root.name);
            _ = try wr.write("   [");

            _ = try wr.write(ns ++ ns);
        }
    }.usage,
    .global_help_fn = struct {
        fn help(root: anytype, wr: anytype, _: mem.Allocator) !void {
            const indent = @TypeOf(root.*).indent_fmt;

            _ = try root.usage(wr);

            _ = try wr.write("(SUB)COMMANDS" ++ ns ++ ns ++ indent ++ indent);
            _ = try wr.write(root.name);
            _ = try wr.write(": ");
            if (active_scheme.one) |v| _ = try wr.write(v);
            _ = try wr.write(root.description);
            if (active_scheme.one) |_| _ = try wr.write(zero);
            _ = try wr.write(ns ++ ns);

            if (root.sub_cmds) |cmds| {
                for (cmds) |cmd| {
                    if (cmd.hidden) continue;
                    _ = try wr.write(indent ++ indent);
                    _ = try wr.write(cmd.name);
                    _ = try wr.write(": ");
                    if (active_scheme.two) |v| _ = try wr.write(v);
                    _ = try wr.write(cmd.description);
                    if (active_scheme.two) |_| _ = try wr.write(zero);
                    _ = try wr.writeByte(nb);
                }
                _ = try wr.writeByte(nb);
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
    }.help,
    .opt_config = .{
        .global_usage_fn = struct {
            pub fn usage(opt: anytype, wr: anytype, _: mem.Allocator) !void {
                _ = try wr.write(@TypeOf(opt.*).long_prefix.?);
                _ = try wr.write(opt.long_name.?);
                _ = try wr.writeByte(' ');

                if (active_scheme.one) |v| _ = try wr.write(v);
                _ = try wr.writeByte('"');
                const val_name = opt.val.name();
                if (val_name.len > 0) {
                    _ = try wr.write(val_name);
                    _ = try wr.writeByte(' ');
                }
                _ = try wr.writeByte('(');
                const child_type = opt.val.childType();
                _ = try wr.write(child_type);
                _ = try wr.write(")\"");
                if (active_scheme.one) |_| _ = try wr.write(zero);

                var default_as_string: ?[]const u8 = null;
                if (mem.eql(u8, child_type, "[]const u8")) {
                    default_as_string = opt.val.generic.string.default_val;
                } else if (mem.eql(u8, child_type, "bool")) {
                    default_as_string = if (opt.val.generic.bool.default_val) |v|
                        if (v) "true" else "false"
                    else
                        null;
                }
                if (default_as_string) |str| {
                    _ = try wr.write(" default: ");
                    _ = try wr.write(str);
                }
            }
        }.usage,
        .global_help_fn = struct {
            pub fn help(opt: anytype, wr: anytype, _: mem.Allocator) !void {
                const indent = @TypeOf(opt.*).indent_fmt.?;
                _ = try wr.write(indent);
                try opt.usage(wr);
                var it = mem.splitScalar(u8, opt.description, nb);
                while (it.next()) |line| {
                    _ = try wr.write(ns ++ indent);
                    if (active_scheme.two) |v| _ = try wr.write(v);
                    _ = try wr.write(line);
                    if (active_scheme.two) |_| _ = try wr.write(zero);
                }
                _ = try wr.writeByte(nb);
            }
        }.help,
        .allow_abbreviated_long_opts = false,
        .allow_opt_val_no_space = true,
        .opt_val_seps = "=:",
        .short_prefix = null,
        .long_prefix = "-",
    },
    .val_config = .{
        .add_base_floats = false,
        .add_base_ints = false,
        .use_slim_base = true,
        .set_behavior = .Last,
        .arg_delims = ",;",
    },
    .global_sub_cmds_mandatory = false,
    .global_case_sensitive = false,
    .indent_fmt = "    ",
});

// Comptime helper functions
fn command(cmd: []const u8, desc: []const u8, cmds: ?[]const CommandT, opts: ?[]const CommandT.OptionT) CommandT {
    return .{ .name = cmd, .description = desc, .sub_cmds = cmds, .opts = opts, .hidden = desc.len == 0 };
}

fn option(opt: []const u8, desc: []const u8, val: CommandT.ValueT) CommandT.OptionT {
    return .{ .name = opt, .long_name = opt, .description = desc, .val = val, .hidden = desc.len == 0 };
}

fn deadlineOption(opt: []const u8, default: []const u8, desc: []const u8) CommandT.OptionT {
    return option(opt, desc, CommandT.ValueT.ofType([]const u8, .{
        .name = "vpxl_deadline",
        .default_val = default,
        .parse_fn = struct {
            pub fn parseDeadline(arg: []const u8, _: mem.Allocator) ![]const u8 {
                const deadlines = [_][]const u8{ "fast", "good", "best" };
                for (deadlines) |str| if (ascii.eqlIgnoreCase(str, arg)) return str;
                return error.DeadlineValueUnsupported;
            }
        }.parseDeadline,
    }));
}

fn pixelFormatOption(opt: []const u8, default: []const u8, desc: []const u8) CommandT.OptionT {
    return option(opt, desc, CommandT.ValueT.ofType([]const u8, .{
        .name = "pixel_format",
        .default_val = default,
        .parse_fn = struct {
            pub fn parsePixelFormat(arg: []const u8, _: mem.Allocator) ![]const u8 {
                const format = [_][]const u8{
                    "yuv420p",
                    "yuva420p",
                    "yuv422p",
                    "yuv440p",
                    "yuv444p",
                    "yuv420p10le",
                    "yuv422p10le",
                    "yuv440p10le",
                    "yuv444p10le",
                    "yuv420p12le",
                    "yuv422p12le",
                    "yuv440p12le",
                    "yuv444p12le",
                    "gbrp",
                    "gbrp10le",
                    "gbrp12le",
                };
                for (format) |str| if (ascii.eqlIgnoreCase(str, arg)) return str;
                return error.PixelFormatUnsupportedByVP9;
            }
        }.parsePixelFormat,
    }));
}

fn typeAndPathOption(opt: []const u8, val: []const u8, desc: []const u8) CommandT.OptionT {
    return option(opt, desc, CommandT.ValueT.ofType([]const u8, .{
        .name = val ++ "_path",
        .parse_fn = struct {
            pub fn parsePath(arg: []const u8, _: mem.Allocator) ![]const u8 {
                os.access(arg, os.F_OK) catch |err| {
                    // Windows doesn't make stdin/out/err available via system path,
                    // so this will have to be handled outside Cova
                    if (mem.eql(u8, arg, "-")) return arg;
                    return err;
                };
                return arg;
            }
        }.parsePath,
    }));
}

fn passOption(opt: []const u8, default: []const u8, desc: []const u8) CommandT.OptionT {
    return option(opt, desc, CommandT.ValueT.ofType([]const u8, .{
        .name = "vpxl_pass",
        .default_val = default,
        .parse_fn = struct {
            pub fn parsePass(arg: []const u8, _: mem.Allocator) ![]const u8 {
                const passes = [_][]const u8{ "only", "first", "second" };
                for (passes) |str| if (ascii.eqlIgnoreCase(str, arg)) return str;
                return error.PassValueUnsupported;
            }
        }.parsePass,
    }));
}

fn gopOption(opt: []const u8, default: []const u8, desc: []const u8) CommandT.OptionT {
    return option(opt, desc, CommandT.ValueT.ofType([]const u8, .{
        .name = "",
        .default_val = default,
        .parse_fn = struct {
            pub fn parseGop(arg: []const u8, _: mem.Allocator) ![]const u8 {
                _ = arg;
                return error.GOPValueUnsupported;
            }
        }.parseGop,
    }));
}

fn boolOption(opt: []const u8, default: bool, desc: []const u8) CommandT.OptionT {
    return option(opt, desc, CommandT.ValueT.ofType(bool, .{
        .name = "",
        .default_val = default,
        .parse_fn = struct {
            pub fn parseBool(arg: []const u8, _: mem.Allocator) !bool {
                const T = [_][]const u8{ "1", "true", "t", "yes", "y" };
                const F = [_][]const u8{ "0", "false", "f", "no", "n" };
                for (T) |str| if (ascii.eqlIgnoreCase(str, arg)) return true;
                for (F) |str| if (ascii.eqlIgnoreCase(str, arg)) return false;
                return error.BooleanValueUnsupported;
            }
        }.parseBool,
    }));
}

const vpxl_cmd: CommandT = command(
    "vpxl",
    " a VP9 encoder by Matt R Bonnette",
    &.{
        command("gloss", "Something to help you navigate this program if you're new to encoding video.", null, null),
        command("xpsnr", "Calculate XPSNR score between two or more (un)compressed inputs.", null, &.{
            typeAndPathOption("in", "input",
                \\Path from which (un)compressed frames are to be demuxed and decoded by FFmpeg for scoring.
                \\This option must be passed more than once.
            ),
        }),
        command("fssim", "Calculate FastSSIM score between two or more (un)compressed inputs.", null, &.{
            typeAndPathOption("in", "input",
                \\Path from which (un)compressed frames are to be demuxed and decoded by FFmpeg for scoring.
                \\This option must be passed more than once.
            ),
        }),
    },
    &.{
        boolOption("h", false, ""),
        boolOption("help", false,
            \\Show this help message and exit.
        ),
        deadlineOption("dl", "good",
            \\VPXL encoding deadline: 
        ),
        pixelFormatOption("pix", "yuv420p10le",
            \\Utilizing the source frames' full bit depth during encoding, ensure the compressed output's
            \\frames are in the given format; VPXL supports encoding to the following: yuv420p yuva420p yuv422p yuv440p
            \\yuv444p yuv420p10le yuv422p10le yuv440p10le yuv444p10le yuv420p12le yuv422p12le yuv440p12le
            \\yuv444p12le gbrp gbrp10le gbrp12le
        ),
        typeAndPathOption("in", "input",
            \\Path from which (un)compressed frames are to be demuxed and decoded by FFmpeg for encoding.
        ),
        typeAndPathOption("out", "output",
            \\Path to which VPXL-compressed and FFmpeg-muxed frames are to be written. FFmpeg will mux to
            \\the container format specified by output_path's file extension.
        ),
        passOption("pass", "only",
            \\VPXL encoding pass to employ: 'only' refers to the only pass of one-pass encoding. 'first'
            \\refers to the first pass of two-pass encoding. 'second' refers to the second pass of two-
            \\pass encoding. 
        ),
        boolOption("pp", false,
            \\At the cost of reduced compatibility, lossily preprocesses input frames for improved coding
            \\efficiency: First, crops out uniform letterboxes and pillarbars within consistent GOPs.
            \\Then, denoises imperceptibly noisy frames. And lastly, converts CFR inputs to VFR and drops
            \\perceptually-duplicate frames.
        ),
        boolOption("resume", true,
            \\Allow automatic resumption of a previously-interrupted encoding; pass 'first' cannot be
            \\resumed.
        ),
        boolOption("ansi", true,
            \\Emit ANSI escape sequences with terminal output when available.
        ),
    },
);

// Runtime code
const ns = "\n";
const nb = '\n';
const zero = "\x1b[0m";

const schemes = [_]ColorScheme{
    ColorScheme{ .one = "\x1b[38;5;220m", .two = "\x1b[38;5;36m" },
    ColorScheme{ .one = "\x1b[38;5;230m", .two = "\x1b[38;5;111m" },
};

const ColorScheme = struct { one: ?[]const u8 = null, two: ?[]const u8 = null };

var active_scheme = ColorScheme{};

fn configureColorScheme() !void {
    // TODO(@p7r0x7): Move this to main() if a PRNG is ever elsewhere required.
    var sfc = rand.Sfc64.init(seed: {
        var tmp: u64 = undefined;
        try os.getrandom(mem.asBytes(&tmp));
        break :seed tmp;
    });
    active_scheme = schemes[sfc.random().int(u64) % schemes.len];
}

fn configureEscapeCodes(pipe: fs.File, it: *cova.ArgIteratorGeneric) !void {
    const flag: bool = flag: {
        defer it.zig.inner.index = 0;
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

pub fn runVPXL(pipe: fs.File, ally: mem.Allocator) !void {
    const wr = pipe.writer();
    try wr.writeByte(nb);
    defer wr.writeByte(nb) catch unreachable;
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

    // Call
    const no_args = no_args: {
        arg_it.zig.inner.index = 1;
        break :no_args arg_it.next() == null;
    };
    arg_it.deinit();
    if (no_args or vpxl_cli.checkOpts(&[_][]const u8{ "h", "help" }, .{})) {
        try vpxl_cli.help(bw);
        try buffered.flush();
    }

    if (builtin.mode == .Debug) try cova.utils.displayCmdInfo(CommandT, &vpxl_cli, ally, bw);
}

// const description: fn (anytype, anytype, anytype) void![]const u8 = undefined;
