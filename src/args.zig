//
// parse cli args into an Args struct
//

pub const Args = struct {
    const params = clap.parseParamsComptime(
        \\    --color <COLOR>       Turn color off and on (auto|off|on)
        \\    --theme <THEME>       Select color theme (auto|dark|light)
        \\-n, --row-numbers         Turn on row numbers
        \\-t, --title <STRING>      Add a title
        \\-w, --width <INT>         Set max table width in columns (0 = auto)
        \\-h, --help                Show help
        \\    --version             Show version number
        \\<FILE>...                 CSV file to process, or "-" for stdin
    );

    // clap parsers
    const parsers = .{
        .COLOR = clap.parsers.enumeration(types.Color),
        .FILE = clap.parsers.string,
        .INT = clap.parsers.int(usize, 10),
        .STRING = clap.parsers.string,
        .THEME = clap.parsers.enumeration(types.Theme),
    };

    // state
    action: ?Action = null,
    config: types.Config = .{},
    filename: ?[]const u8 = null,
    err_str: ?[]const u8 = null,

    pub fn init(alloc: std.mem.Allocator, argv: []const []const u8) !Args {
        var diagnostics: clap.Diagnostic = .{};
        const args = parse(alloc, argv, &diagnostics) catch |err| {
            var buf: [512]u8 = undefined;
            return .{
                .action = .fatal,
                .err_str = try alloc.dupe(u8, errorString(&buf, err, &diagnostics)),
            };
        };

        // quick check of file here
        if (args.filename) |filename| {
            if (!std.mem.eql(u8, filename, "-") and !util.fileExists(filename)) {
                return .{
                    .action = .fatal,
                    .err_str = try std.fmt.allocPrint(alloc, "Could not read file '{s}'", .{filename}),
                };
            }
        }

        return args;
    }

    fn parse(
        alloc: std.mem.Allocator,
        argv: []const []const u8,
        diagnostic: *clap.Diagnostic,
    ) anyerror!Args {
        if (builtin.os.tag == .windows) return error.Windows;

        var iter = clap.args.SliceIterator{ .args = argv };
        var res = try clap.parseEx(clap.Help, &params, parsers, &iter, .{
            .allocator = alloc,
            .diagnostic = diagnostic,
        });
        defer res.deinit();

        //
        // these are early exits
        //

        if (res.args.help > 0) return .{ .action = .help };
        if (res.args.version > 0) return .{ .action = .version };

        //
        // copy args into Config
        //

        var config: types.Config = .{};
        if (res.args.color) |v| config.color = v;
        if (res.args.theme) |v| config.theme = v;
        if (res.args.title) |v| config.title = v;
        if (res.args.width) |v| config.width = v;
        config.row_numbers = @field(res.args, "row-numbers") > 0;

        //
        // now handle filename
        //

        const files = res.positionals[0];
        switch (files.len) {
            0 => {
                // stdin, could be the naked case
                if (std.posix.isatty(std.fs.File.stdin().handle)) {
                    if (argv.len != 0) return error.CouldNotReadStdin;
                    return .{ .action = .banner };
                }
                return .{ .config = config };
            },
            1 => return .{ .config = config, .filename = files[0] },
            else => return error.TooManyArguments,
        }
    }

    fn errorString(buf: *[512]u8, err: anyerror, diag: *clap.Diagnostic) []const u8 {
        return switch (err) {
            error.DoesntTakeValue, error.MissingValue, error.InvalidArgument => blk: {
                var writer = std.Io.Writer.fixed(buf);
                diag.report(&writer, err) catch {};
                break :blk util.strip(u8, writer.buffered());
            },
            error.CouldNotReadStdin => "Could not read from stdin",
            error.TooManyArguments => "Too many file arguments",
            error.Windows => "Windows is not yet supported",
            else => "Argument parsing failed",
        };
    }

    pub fn writeHelp(writer: *std.Io.Writer) !void {
        try writer.writeAll("Usage: tennis [options] <FILE>\n\nOptions:\n");
        try clap.help(writer, clap.Help, &params, .{
            .description_on_new_line = false,
            .spacing_between_parameters = 0,
        });
    }
};

// these are early exits for main. some results in exit 0, some exit 1.
pub const Action = enum { banner, fatal, help, version };

//
// tests
//

test "parse args accepts dash positional" {
    const out = try Args.init(std.testing.allocator, &.{"-"});
    try std.testing.expectEqual(null, out.action);
    try std.testing.expect(out.filename != null);
    try std.testing.expectEqualStrings("-", out.filename.?);
}

test "parse parses options" {
    var diag: clap.Diagnostic = .{};
    const out = try Args.parse(std.testing.allocator, &.{
        "--color",
        "off",
        "--theme",
        "light",
        "--title",
        "foo",
        "--width",
        "80",
        "-n",
        "-",
    }, &diag);

    try std.testing.expectEqual(null, out.action);
    try std.testing.expectEqual(types.Color.off, out.config.color);
    try std.testing.expectEqual(types.Theme.light, out.config.theme);
    try std.testing.expectEqualStrings("foo", out.config.title);
    try std.testing.expectEqual(80, out.config.width);
    try std.testing.expect(out.config.row_numbers);
    try std.testing.expectEqualStrings("-", out.filename.?);
}

test "parse rejects too many file arguments" {
    var diag: clap.Diagnostic = .{};
    try std.testing.expectError(error.TooManyArguments, Args.parse(std.testing.allocator, &.{
        "a.csv",
        "b.csv",
    }, &diag));
}

test "parse rejects old color value never" {
    var diag: clap.Diagnostic = .{};
    try std.testing.expectError(error.NameNotPartOfEnum, Args.parse(std.testing.allocator, &.{
        "--color",
        "never",
    }, &diag));
}

test "init sets fatal action for missing file" {
    const out = try Args.init(std.testing.allocator, &.{"definitely-not-a-real-file.csv"});
    defer if (out.err_str) |msg| std.testing.allocator.free(msg);
    try std.testing.expectEqual(Action.fatal, out.action.?);
    try std.testing.expect(out.err_str != null);
    try std.testing.expect(std.mem.indexOf(u8, out.err_str.?, "definitely-not-a-real-file.csv") != null);
}

const builtin = @import("builtin");
const clap = @import("clap");
const std = @import("std");
const types = @import("types.zig");
const util = @import("util.zig");
