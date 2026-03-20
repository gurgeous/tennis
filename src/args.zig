//
// parse cli args into an Args struct
//

pub const CompletionShell = enum { bash, zsh };

pub const Args = struct {
    pub const help =
        \\ Usage: tennis [options...] <file.csv>     # print file.csv
        \\        tennis [options...]                # print csv from stdin
        \\
        \\  -n, --row-numbers         Turn on row numbers
        \\  -t, --title <string>      Add a title to the table
        \\
        \\      --border <border>     Table border style (rounded|thin|double|...)
        \\      --color <color>       Turn color off and on (on|off|auto)
        \\      --completion <shell>  Print a shell completion script (bash|zsh)
        \\      --delimiter <char>    CSV delim (can be any char or "tab")
        \\      --digits <int>        Digits after decimal for float columns (1-6)
        \\      --head <int>          Show first N rows
        \\      --tail <int>          Show last N rows
        \\      --theme <theme>       Select color theme (auto|dark|light)
        \\      --vanilla             Disable numeric formatting entirely
        \\      --width <int>         Set max table width in chars
        \\      --help                Get help
        \\      --version             Show version number and exit
        \\
    ;

    const params = clap.parseParamsComptime(
        \\    --border <BORDER>
        \\    --color <COLOR>
        \\    --completion <SHELL>
        \\    --head <INT>
        \\    --tail <INT>
        \\    --theme <THEME>
        \\-d, --delimiter <CHAR>
        \\-n, --row-numbers
        \\-t, --title <STRING>
        \\-w, --width <INT>
        \\    --digits <INT>
        \\    --vanilla
        \\-h, --help
        \\    --version
        \\<FILE>...
    );

    // clap parsers
    const parsers = .{
        .BORDER = clap.parsers.enumeration(border.BorderName),
        .CHAR = parseChar,
        .COLOR = clap.parsers.enumeration(types.Color),
        .FILE = clap.parsers.string,
        .INT = clap.parsers.int(usize, 10),
        .SHELL = clap.parsers.enumeration(CompletionShell),
        .STRING = clap.parsers.string,
        .THEME = clap.parsers.enumeration(types.Theme),
    };

    fn parseChar(input: []const u8) error{InvalidArgument}!u8 {
        if (input.len == 1 and std.ascii.isPrint(input[0]) and input[0] < 0x7f) return input[0];
        if (std.mem.eql(u8, input, "tab")) return '\t';
        if (std.mem.eql(u8, input, "\\t")) return '\t';
        return error.InvalidArgument;
    }

    // state
    action: ?Action = null,
    completion: ?CompletionShell = null,
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

    pub fn deinit(self: Args, alloc: std.mem.Allocator) void {
        if (self.err_str) |msg| alloc.free(msg);
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
        if (res.args.completion) |shell| return .{ .action = .completion, .completion = shell };
        if (res.args.version > 0) return .{ .action = .version };

        //
        // copy args into Config
        //

        var config: types.Config = .{};
        if (res.args.border) |v| config.border = v;
        if (res.args.color) |v| config.color = v;
        // note that 0 means "unset" and we try to sniff later before defaulting to comma
        config.delimiter = if (res.args.delimiter) |v| v else 0;
        if (res.args.digits) |v| {
            if (v < 1 or v > 6) return error.InvalidDigits;
            config.digits = v;
        }
        if (res.args.head) |v| {
            if (v == 0) return error.InvalidHeadValue;
            config.head = v;
        }
        if (res.args.tail) |v| {
            if (v == 0) return error.InvalidTailValue;
            config.tail = v;
            if (config.head > 0) return error.InvalidHeadTail;
        }
        if (res.args.theme) |v| config.theme = v;
        if (res.args.title) |v| config.title = v;
        if (res.args.width) |v| config.width = v;
        config.row_numbers = @field(res.args, "row-numbers") > 0;
        config.vanilla = res.args.vanilla > 0;

        //
        // now handle filename
        //

        return try resolveInput(config, argv.len, res.positionals[0], std.posix.isatty(std.fs.File.stdin().handle));
    }

    fn errorString(buf: *[512]u8, err: anyerror, diag: *clap.Diagnostic) []const u8 {
        return switch (err) {
            error.CouldNotReadStdin => "Could not read from stdin",
            error.InvalidDigits => "Digits must be between 1 and 6",
            error.InvalidHeadTail => "Use --head or --tail, not both",
            error.InvalidHeadValue => "Head must be greater than 0",
            error.InvalidTailValue => "Tail must be greater than 0",
            error.TooManyArguments => "Too many file arguments",
            error.Windows => "Windows is not yet supported",
            else => blk: {
                var writer = std.Io.Writer.fixed(buf);
                diag.report(&writer, err) catch {};
                const msg = util.strip(u8, writer.buffered());
                break :blk if (msg.len > 0) msg else "Argument parsing failed";
            },
        };
    }

    fn resolveInput(
        config: types.Config,
        argv_len: usize,
        files: []const []const u8,
        stdin_is_tty: bool,
    ) !Args {
        switch (files.len) {
            0 => {
                if (stdin_is_tty) {
                    if (argv_len != 0) return error.CouldNotReadStdin;
                    return .{ .action = .banner };
                }
                return .{ .config = config };
            },
            1 => return .{ .config = config, .filename = files[0] },
            else => return error.TooManyArguments,
        }
    }
};

// these are early exits for main. some results in exit 0, some exit 1.
pub const Action = enum { banner, completion, fatal, help, version };

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
        "--border",
        "double",
        "--color",
        "off",
        "--digits",
        "4",
        "--head",
        "5",
        "--theme",
        "light",
        "--title",
        "foo",
        "--vanilla",
        "--width",
        "80",
        "-n",
        "-",
    }, &diag);

    try std.testing.expectEqual(null, out.action);
    try std.testing.expectEqual(border.BorderName.double, out.config.border);
    try std.testing.expectEqual(types.Color.off, out.config.color);
    try std.testing.expectEqual(@as(usize, 4), out.config.digits);
    try std.testing.expectEqual(@as(usize, 5), out.config.head);
    try std.testing.expectEqual(types.Theme.light, out.config.theme);
    try std.testing.expectEqualStrings("foo", out.config.title);
    try std.testing.expect(out.config.vanilla);
    try std.testing.expectEqual(80, out.config.width);
    try std.testing.expect(out.config.row_numbers);
    try std.testing.expectEqualStrings("-", out.filename.?);
}

test "parse parses delimiter option" {
    var diag: clap.Diagnostic = .{};
    const out = try Args.parse(std.testing.allocator, &.{
        "--delimiter",
        ";",
        "-",
    }, &diag);
    try std.testing.expectEqual(@as(u8, ';'), out.config.delimiter);
}

test "parse parses border option" {
    var diag: clap.Diagnostic = .{};
    const out = try Args.parse(std.testing.allocator, &.{
        "--border",
        "compact_double",
        "-",
    }, &diag);
    try std.testing.expectEqual(border.BorderName.compact_double, out.config.border);
}

test "parse parses completion option" {
    var diag: clap.Diagnostic = .{};
    const out = try Args.parse(std.testing.allocator, &.{
        "--completion",
        "zsh",
    }, &diag);
    try std.testing.expectEqual(Action.completion, out.action.?);
    try std.testing.expectEqual(CompletionShell.zsh, out.completion.?);
}

test "parse parses short delimiter option" {
    var diag: clap.Diagnostic = .{};
    const out = try Args.parse(std.testing.allocator, &.{
        "-d",
        ";",
        "-",
    }, &diag);
    try std.testing.expectEqual(@as(u8, ';'), out.config.delimiter);
}

test "parse parses tab delimiter name" {
    var diag: clap.Diagnostic = .{};
    const out = try Args.parse(std.testing.allocator, &.{
        "--delimiter",
        "tab",
        "-",
    }, &diag);
    try std.testing.expectEqual(@as(u8, '\t'), out.config.delimiter);
}

test "parse parses tab delimiter escape" {
    var diag: clap.Diagnostic = .{};
    const out = try Args.parse(std.testing.allocator, &.{
        "--delimiter",
        "\\t",
        "-",
    }, &diag);
    try std.testing.expectEqual(@as(u8, '\t'), out.config.delimiter);
}

test "parse rejects multi-char delimiter" {
    var diag: clap.Diagnostic = .{};
    try std.testing.expectError(error.InvalidArgument, Args.parse(std.testing.allocator, &.{
        "--delimiter",
        ";;",
    }, &diag));
}

test "parse rejects non-printable delimiter" {
    var diag: clap.Diagnostic = .{};
    try std.testing.expectError(error.InvalidArgument, Args.parse(std.testing.allocator, &.{
        "--delimiter",
        "\x01",
    }, &diag));
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

test "parse rejects invalid border value" {
    var diag: clap.Diagnostic = .{};
    try std.testing.expectError(error.NameNotPartOfEnum, Args.parse(std.testing.allocator, &.{
        "--border",
        "bogus",
    }, &diag));
}

test "parse returns help action" {
    var diag: clap.Diagnostic = .{};
    const out = try Args.parse(std.testing.allocator, &.{"--help"}, &diag);
    try std.testing.expectEqual(Action.help, out.action.?);
}

test "parse returns version action" {
    var diag: clap.Diagnostic = .{};
    const out = try Args.parse(std.testing.allocator, &.{"--version"}, &diag);
    try std.testing.expectEqual(Action.version, out.action.?);
}

test "errorString handles direct mapped errors" {
    var buf: [512]u8 = undefined;
    var diag: clap.Diagnostic = .{};

    try std.testing.expectEqualStrings("Digits must be between 1 and 6", Args.errorString(&buf, error.InvalidDigits, &diag));
    try std.testing.expectEqualStrings("Could not read from stdin", Args.errorString(&buf, error.CouldNotReadStdin, &diag));
    try std.testing.expectEqualStrings("Windows is not yet supported", Args.errorString(&buf, error.Windows, &diag));
    try std.testing.expectEqualStrings("Error while parsing arguments: OutOfMemory", Args.errorString(&buf, error.OutOfMemory, &diag));
}

test "parse rejects invalid digits" {
    var diag: clap.Diagnostic = .{};
    try std.testing.expectError(error.InvalidDigits, Args.parse(std.testing.allocator, &.{
        "--digits",
        "0",
    }, &diag));
    try std.testing.expectError(error.InvalidDigits, Args.parse(std.testing.allocator, &.{
        "--digits",
        "7",
    }, &diag));
}

test "parse rejects head and tail together" {
    var diag: clap.Diagnostic = .{};
    try std.testing.expectError(error.InvalidHeadTail, Args.parse(std.testing.allocator, &.{
        "--head",
        "1",
        "--tail",
        "1",
    }, &diag));
}

test "parse rejects zero head and tail" {
    var diag: clap.Diagnostic = .{};
    try std.testing.expectError(error.InvalidHeadValue, Args.parse(std.testing.allocator, &.{
        "--head",
        "0",
    }, &diag));
    try std.testing.expectError(error.InvalidTailValue, Args.parse(std.testing.allocator, &.{
        "--tail",
        "0",
    }, &diag));
}

test "errorString reports clap diagnostics" {
    var buf: [512]u8 = undefined;
    var diag: clap.Diagnostic = .{};
    _ = Args.parse(std.testing.allocator, &.{
        "--width",
    }, &diag) catch |err| {
        const msg = Args.errorString(&buf, err, &diag);
        try std.testing.expect(std.mem.indexOf(u8, msg, "--width") != null);
        try std.testing.expect(std.mem.indexOf(u8, msg, "require") != null or std.mem.indexOf(u8, msg, "value") != null);
        return;
    };
    return error.TestUnexpectedResult;
}

test "errorString reports enum diagnostics" {
    var buf: [512]u8 = undefined;
    var diag: clap.Diagnostic = .{};
    _ = Args.parse(std.testing.allocator, &.{
        "--color",
        "bogus",
    }, &diag) catch |err| {
        const msg = Args.errorString(&buf, err, &diag);
        try std.testing.expect(std.mem.indexOf(u8, msg, "NameNotPartOfEnum") != null);
        return;
    };
    return error.TestUnexpectedResult;
}

test "errorString reports invalid int diagnostics" {
    var buf: [512]u8 = undefined;
    var diag: clap.Diagnostic = .{};
    _ = Args.parse(std.testing.allocator, &.{
        "--digits",
        "bogus",
    }, &diag) catch |err| {
        const msg = Args.errorString(&buf, err, &diag);
        try std.testing.expect(std.mem.indexOf(u8, msg, "InvalidCharacter") != null);
        return;
    };
    return error.TestUnexpectedResult;
}

test "resolveInput handles stdin cases" {
    const config: types.Config = .{};

    const banner = try Args.resolveInput(config, 0, &.{}, true);
    try std.testing.expectEqual(Action.banner, banner.action.?);

    try std.testing.expectError(error.CouldNotReadStdin, Args.resolveInput(config, 1, &.{}, true));

    const stdin = try Args.resolveInput(config, 1, &.{}, false);
    try std.testing.expectEqual(null, stdin.action);
    try std.testing.expectEqual(null, stdin.filename);
}

test "init sets fatal action for parse failures" {
    const out = try Args.init(std.testing.allocator, &.{"--bogus"});
    defer out.deinit(std.testing.allocator);
    try std.testing.expectEqual(Action.fatal, out.action.?);
    try std.testing.expect(out.err_str != null);
    try std.testing.expect(std.mem.indexOf(u8, out.err_str.?, "--bogus") != null);
}

test "init keeps enum parse diagnostics" {
    const out = try Args.init(std.testing.allocator, &.{ "--color", "bogus" });
    defer out.deinit(std.testing.allocator);
    try std.testing.expectEqual(Action.fatal, out.action.?);
    try std.testing.expect(out.err_str != null);
    try std.testing.expect(std.mem.indexOf(u8, out.err_str.?, "NameNotPartOfEnum") != null);
}

test "init sets fatal action for missing file" {
    const out = try Args.init(std.testing.allocator, &.{"definitely-not-a-real-file.csv"});
    defer out.deinit(std.testing.allocator);
    try std.testing.expectEqual(Action.fatal, out.action.?);
    try std.testing.expect(out.err_str != null);
    try std.testing.expect(std.mem.indexOf(u8, out.err_str.?, "definitely-not-a-real-file.csv") != null);
}

const border = @import("border.zig");
const builtin = @import("builtin");
const clap = @import("clap");
const std = @import("std");
const types = @import("types.zig");
const util = @import("util.zig");
