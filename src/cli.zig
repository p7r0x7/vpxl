const std = @import("std");
const cova = @import("cova");
const io = @import("std").io;
const os = @import("std").os;
const fmt = @import("std").fmt;
const mem = @import("std").mem;
const ascii = @import("std").ascii;
const builtin = @import("builtin");

const blurple = "\x1b[38;5;111m";
const butter = "\x1b[38;5;230m";
const zero = "\x1b[0m";

/// Cova configuration type identity
pub const CommandT = cova.Command.Custom(.{
    .indent_fmt = "    ",
    .subcmds_help_fmt = "{s}:\t" ++ butter ++ "{s}" ++ zero,
    .opt_config = .{
        .usage_fn = struct {
            pub fn usage(self: anytype, writer: anytype, _: mem.Allocator) !void {
                const child = self.val.childType();
                const val_name = self.val.name();
                try writer.print("{?s}{?s} " ++ butter ++ "\"{s}{s}({s})\"" ++ zero, .{
                    @TypeOf(self.*).long_prefix orelse "",
                    self.long_name orelse "",
                    val_name,
                    if (val_name.len > 0) " " else "",
                    child,
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
        .help_fn = struct {
            pub fn help(self: anytype, writer: anytype, _: mem.Allocator) !void {
                try self.usage(writer);
                try writer.print(
                    "\n{s}{s}" ++ blurple ++ "{s}" ++ zero ++ "\n",
                    .{ @TypeOf(self.*).indent_fmt orelse "", @TypeOf(self.*).indent_fmt orelse "", self.description },
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
        .vals_help_fmt = "{s} ({s}):\t" ++ butter ++ "{s}" ++ zero,
        .set_behavior = .Last,
        .arg_delims = ",;",
    },
});

fn subCommandOrCommand(cmd: []const u8, desc: []const u8, sub_cmds: ?[]const CommandT, opts: ?[]const CommandT.OptionT) CommandT {
    return .{ .name = cmd, .description = desc, .sub_cmds = sub_cmds, .opts = opts };
}

fn boolOption(opt: []const u8, default: bool, desc: []const u8) CommandT.OptionT {
    return .{
        .name = opt,
        .long_name = opt,
        .description = blurple ++ desc ++ zero,
        .val = CommandT.ValueT.ofType(bool, .{
            .name = "",
            .default_val = default,
            .parse_fn = struct {
                pub fn parseBool(arg: []const u8, _: mem.Allocator) !bool {
                    const T = [_][]const u8{ "1", "true", "t", "yes", "y" };
                    const F = [_][]const u8{ "0", "false", "f", "no", "n" };
                    for (T) |str| if (ascii.eqlIgnoreCase(str, arg)) return true;
                    for (F) |str| if (ascii.eqlIgnoreCase(str, arg)) return false;
                    return error.InvalidBooleanValue;
                }
            }.parseBool,
        }),
    };
}

fn containerAndPathOption(opt: []const u8, val: []const u8, desc: []const u8) CommandT.OptionT {
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

fn deadlineAndPixelOption(opt: []const u8, val: []const u8, desc: []const u8) CommandT.OptionT {
    _ = desc;
    _ = val;
    _ = opt;
}

fn gopOption(opt: []const u8, default: u32, desc: []const u8) CommandT.OptionT {
    _ = desc;
    _ = default;
    _ = opt;
}

const vpxl_cmd = subCommandOrCommand(
    "vpxl",
    "a VP9 encoder by Matt R Bonnette",
    &.{
        subCommandOrCommand("xpsnr", "Calculate XPSNR score between two or more uncompressed inputs.", null, &.{
            containerAndPathOption("mkv", "input", "Path from which uncompressed frames (in the Matroska format) are to be read."),
            containerAndPathOption("y4m", "input", "Path from which uncompressed frames (in the YUV4MPEG2 format) are to be read."),
            containerAndPathOption("yuv", "input", "Path from which uncompressed frames (in plain YUV format) are to be read."),
        }),
        subCommandOrCommand("fssim", "Calculate FastSSIM score between two or more uncompressed inputs.", null, &.{
            containerAndPathOption("mkv", "input", "Path from which uncompressed frames (in the Matroska format) are to be read."),
            containerAndPathOption("y4m", "input", "Path from which uncompressed frames (in the YUV4MPEG2 format) are to be read."),
            containerAndPathOption("yuv", "input", "Path from which uncompressed frames (in plain YUV format) are to be read."),
        }),
    },
    &.{
        containerAndPathOption("mkv", "input",
            \\Path from which uncompressed frames (in the Matroska format) are to be read; mutually
            \\        exclusive with -y4m and -yuv.
        ),
        containerAndPathOption("y4m", "input",
            \\Path from which uncompressed frames (in the YUV4MPEG2 format) are to be read; mutually
            \\        exclusive with -mkv and -yuv.
        ),
        containerAndPathOption("yuv", "input",
            \\Path from which uncompressed frames (in plain YUV format) are to be read; mutually
            \\        exclusive with -mkv and -y4m.
        ),
        containerAndPathOption("webm", "output",
            \\Path to which compressed VP9 frames are to be written; mutually exclusive with -ivf.
        ),
        containerAndPathOption("ivf", "output",
            \\Path to which compressed VP9 frames are to be written; mutually exclusive with -webm.
        ),
        boolOption("resume", true,
            \\Don't be dummy and disable this, this is necessary for thine happiness <3.
        ),
    },
);

// Runtime code
pub fn runVPXL(buffered: anytype, ally: mem.Allocator) !void {
    const bw = buffered.writer();
    const h = os.isatty(os.STDOUT_FILENO);
    _ = h;

    const vpxl_cli = try vpxl_cmd.init(ally, .{});
    defer vpxl_cli.deinit();

    var arg_it = try cova.ArgIteratorGeneric.init(ally);
    defer arg_it.deinit();

    cova.parseArgs(&arg_it, CommandT, &vpxl_cli, bw, .{ .auto_handle_usage_help = false }) catch |err| switch (err) {
        error.TooManyValues,
        error.UnrecognizedArgument,
        error.UnexpectedArgument,
        error.CouldNotParseOption,
        => {},
        else => return err,
    };
    try vpxl_cli.help(bw);
    try buffered.flush();

    const in_fmt = try vpxl_cli.matchOpts(&.{ "mkv", "y4m", "yuv" }, .{ .logic = .XOR });
    _ = in_fmt;
    const out_fmt = try vpxl_cli.matchOpts(&.{ "webm", "ivf" }, .{ .logic = .XOR });
    _ = out_fmt;

    // Handle in_fmt and out_fmt
    if (builtin.mode == .Debug) try cova.utils.displayCmdInfo(CommandT, &vpxl_cli, ally, bw);
    try buffered.flush();
}
