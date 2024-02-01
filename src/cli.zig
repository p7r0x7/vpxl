const cova = @import("cova");
const io = @import("std").io;
const os = @import("std").os;
const fmt = @import("std").fmt;
const mem = @import("std").mem;
const ascii = @import("std").ascii;
const builtin = @import("builtin");

var blurple = "\x1b[38;5;111m";
var butter = "\x1b[38;5;230m";
var zero = "\x1b[0m";

/// Cova configuration type identity
pub const CommandT = cova.Command.Custom(.{
    .indent_fmt = "    ",
    .subcmds_help_fmt = "{s}:\t{s}",
    .opt_config = .{
        .global_usage_fn = struct {
            pub fn usage(self: anytype, writer: anytype, _: mem.Allocator) !void {
                const child = self.val.childType();
                const val_name = self.val.name();

                try writer.print("{?s}{?s} {s}\"{s}{s}({s})\"{s}", .{
                    @TypeOf(self.*).long_prefix orelse "",
                    self.long_name orelse "",
                    butter,
                    val_name,
                    if (val_name.len > 0) " " else "",
                    child,
                    zero,
                });
                if (mem.eql(u8, child, "bool")) {
                    const val: ?bool = self.val.generic.bool.default_val;
                    if (val) |v| try writer.print(" default: {any}", .{v});
                } else if (mem.eql(u8, child, "[]const u8")) {
                    const val: ?[]const u8 = self.val.generic.string.default_val;
                    if (val) |v| try writer.print(" default: {any}", .{v});
                }
            }
        }.usage,
        .global_help_fn = struct {
            pub fn help(self: anytype, writer: anytype, _: mem.Allocator) !void {
                try self.usage(writer);
                try writer.print(
                    "\n{s}{s}{s}{s}{s}\n",
                    .{
                        @TypeOf(self.*).indent_fmt orelse "",
                        @TypeOf(self.*).indent_fmt orelse "",
                        blurple,
                        self.description,
                        zero,
                    },
                );
            }
        }.help,
        .allow_abbreviated_long_opts = false,
        .allow_opt_val_no_space = true,
        .opt_val_seps = "=:",
        .short_prefix = null,
        .long_prefix = "-",
    },
    .val_config = .{
        .vals_help_fmt = "{s} ({s}):\t{s}",
        .set_behavior = .Last,
        .arg_delims = ",;",
    },
});

fn subCommandOrCommand(cmd: []const u8, desc: []const u8, sub_cmds: ?[]const CommandT, opts: ?[]const CommandT.OptionT) CommandT {
    return .{ .name = cmd, .description = desc, .sub_cmds = sub_cmds, .opts = opts };
}

fn presetAndPixelOption(opt: []const u8, desc: []const u8) CommandT.OptionT {
    return .{
        .name = opt,
        .long_name = opt,
        .description = desc,
        .val = CommandT.ValueT.ofType([]const u8, .{
            .name = "pixel_format",
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
        }),
    };
}

fn typeAndPathOption(opt: []const u8, val: []const u8, desc: []const u8) CommandT.OptionT {
    return .{
        .name = opt,
        .long_name = opt,
        .description = desc,
        .val = CommandT.ValueT.ofType([]const u8, .{
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
        }),
    };
}

fn passOption(opt: []const u8, default: []const u8, desc: []const u8) CommandT.OptionT {
    return .{
        .name = opt,
        .long_name = opt,
        .description = desc,
        .val = CommandT.ValueT.ofType([]const u8, .{
            .name = "",
            .default_val = default,
            .parse_fn = struct {
                pub fn parsePass(arg: []const u8, _: mem.Allocator) ![]const u8 {
                    const passes = [_][]const u8{ "only", "first", "second" };
                    for (passes) |str| if (ascii.eqlIgnoreCase(str, arg)) return str;
                    return error.PassValueUnsupported;
                }
            }.parsePass,
        }),
    };
}

fn gopOption(opt: []const u8, default: []const u8, desc: []const u8) CommandT.OptionT {
    return .{
        .name = opt,
        .long_name = opt,
        .description = desc,
        .val = CommandT.ValueT.ofType([]const u8, .{
            .name = "",
            .default_val = default,
            .parse_fn = struct {
                pub fn parseGop(arg: []const u8, _: mem.Allocator) ![]const u8 {
                    _ = arg;
                    return error.GopValueUnsupported;
                }
            }.parseGop,
        }),
    };
}

fn boolOption(opt: []const u8, default: bool, desc: []const u8) CommandT.OptionT {
    return .{
        .name = opt,
        .long_name = opt,
        .description = desc,
        .val = CommandT.ValueT.ofType(bool, .{
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
        }),
    };
}

const vpxl_cmd = subCommandOrCommand(
    "vpxl",
    "a VP9 encoder by Matt R Bonnette",
    &.{
        subCommandOrCommand("glossary", "Something to help you navigate this program if you're new to video encoding.", null, null),
        subCommandOrCommand("xpsnr", "Calculate XPSNR score between two or more (un)compressed inputs.", null, &.{
            typeAndPathOption("in", "input",
                \\Path from which (un)compressed frames are to be demuxed and decoded by FFmpeg for scoring.
                \\This option must be passed more than once.
            ),
        }),
        subCommandOrCommand("fssim", "Calculate FastSSIM score between two or more (un)compressed inputs.", null, &.{
            typeAndPathOption("in", "input",
                \\Path from which (un)compressed frames are to be demuxed and decoded by FFmpeg for scoring.
                \\This option must be passed more than once.
            ),
        }),
    },
    &.{
        presetAndPixelOption("fast",
            \\Appropriately convert pixels to the given format and encode to VP9 using VPXL's fast preset.
        ),
        presetAndPixelOption("good",
            \\Appropriately convert pixels to the given format and encode to VP9 using VPXL's good preset.
        ),
        presetAndPixelOption("best",
            \\Appropriately convert pixels to the given format and encode to VP9 using VPXL's best preset.
        ),
        typeAndPathOption("in", "input",
            \\Path from which (un)compressed frames are to be demuxed and decoded by FFmpeg for encoding.
        ),
        typeAndPathOption("out", "output",
            \\Path to which VPXL-compressed and FFmpeg-muxed frames are to be written.
        ),
        boolOption("pre", false,
            \\Allow lossy preprocessing of input frames, improving efficiency but reducing compatibility.
        ),
        boolOption("resume", true,
            \\Allow automatic resumption of a previously-interrupted encoding.
        ),
        boolOption("ansi", true,
            \\Emit ANSI escape sequences with terminal output.
        ),
    },
);

// Runtime code
pub fn runVPXL(buffered: anytype, ally: mem.Allocator) !void {
    const bw = buffered.writer();
    const vpxl_cli = try vpxl_cmd.init(ally, .{});
    defer vpxl_cli.deinit();

    var arg_it = try cova.ArgIteratorGeneric.init(ally);
    defer arg_it.deinit();

    cova.parseArgs(&arg_it, CommandT, &vpxl_cli, bw, .{
        .auto_handle_usage_help = true,
        .enable_opt_termination = true,
        .err_reaction = .Help
    }) catch |err| switch (err) {
        error.CommandNotInitialized,
        error.UnrecognizedArgument,
        error.UnexpectedArgument,
        error.TooManyValues,
        => unreachable,
        error.ExpectedSubCommand => {},
        else => return err,
    };
    try buffered.flush();

    // Handle in_fmt and out_fmt
    if (builtin.mode == .Debug) try cova.utils.displayCmdInfo(CommandT, &vpxl_cli, ally, bw);
    try buffered.flush();
}
