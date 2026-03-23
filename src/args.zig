//
// parse cli args into an Args struct
//

// Shell names supported by the completion generator.
pub const CompletionShell = enum { bash, zsh };

// Parsed CLI state plus any early-exit action.
pub const Args = struct {
    pub const help =
        \\ Usage: tennis [options...] <file.csv>     # print file.csv
        \\        tennis [options...]                # print csv from stdin
        \\
        \\  -n, --row-numbers         Turn on row numbers
        \\  -t, --title <string>      Add a title to the table
        \\  -r, --reverse             Reverse row order (helpful when sorting)
        \\
        \\      --border <border>     Table border style (rounded|thin|double|...)
        \\      --color <color>       Turn color off and on (on|off|auto)
        \\      --delimiter <char>    CSV delim (can be any char or "tab")
        \\      --digits <int>        Digits after decimal for float columns (1-6)
        \\      --theme <theme>       Select color theme (auto|dark|light)
        \\      --vanilla             Disable numeric formatting entirely
        \\      --width <int>         Set max table width in chars
        \\
        \\      --select <headers>    Show one or more comma-separated headers
        \\      --sort <headers>      Sort by one or more comma-separated headers
        \\      --head <int>          Show first N rows
        \\      --tail <int>          Show last N rows
        \\
        \\      --completion <shell>  Print a shell completion script (bash|zsh)
        \\      --help                Get help
        \\      --version             Show version number and exit
        \\
    ;

    const params = clap.parseParamsComptime(
        \\    --border <BORDER>
        \\    --color <COLOR>
        \\    --completion <SHELL>
        \\    --head <INT>
        \\    --sort <STRING>
        \\    --tail <INT>
        \\    --theme <THEME>
        \\-d, --delimiter <CHAR>
        \\-n, --row-numbers
        \\-r, --reverse
        \\-t, --title <STRING>
        \\-w, --width <INT>
        \\    --digits <INT>
        \\    --select <STRING>
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

    // Parse a delimiter argument into one ASCII byte.
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

    // Parse argv into structured CLI state.
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

    // Release any owned argument error text.
    pub fn deinit(self: Args, alloc: std.mem.Allocator) void {
        if (self.err_str) |msg| alloc.free(msg);
    }

    // Parse argv and map supported flags into config.
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
        config.reverse = res.args.reverse > 0;
        if (res.args.select) |v| config.select = v;
        if (res.args.sort) |v| config.sort = v;
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

    // Convert a parse failure into a short human-readable error string.
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

    // Resolve positional input into stdin, file, or banner behavior.
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

// These are early exits for main, with mixed success and failure cases.
pub const Action = enum { banner, completion, fatal, help, version };

//
// testing
//

test "parse args accepts dash positional" {
    const out = try Args.init(testing.allocator, &.{"-"});
    try testing.expectEqual(null, out.action);
    try testing.expect(out.filename != null);
    try testing.expectEqualStrings("-", out.filename.?);
}

test "parse option cases" {
    const out = try parseTest(&.{
        "--border",
        "double",
        "--color",
        "off",
        "--digits",
        "4",
        "--head",
        "5",
        "--reverse",
        "--select",
        "name,score",
        "--sort",
        "score,name",
        "--theme",
        "light",
        "--title",
        "foo",
        "--vanilla",
        "--width",
        "80",
        "-n",
        "-",
    });

    try testing.expectEqual(null, out.action);
    try testing.expectEqual(border.BorderName.double, out.config.border);
    try testing.expectEqual(types.Color.off, out.config.color);
    try testing.expectEqual(@as(usize, 4), out.config.digits);
    try testing.expectEqual(@as(usize, 5), out.config.head);
    try testing.expect(out.config.reverse);
    try testing.expectEqualStrings("name,score", out.config.select);
    try testing.expectEqualStrings("score,name", out.config.sort);
    try testing.expectEqual(types.Theme.light, out.config.theme);
    try testing.expectEqualStrings("foo", out.config.title);
    try testing.expect(out.config.vanilla);
    try testing.expectEqual(80, out.config.width);
    try testing.expect(out.config.row_numbers);
    try testing.expectEqualStrings("-", out.filename.?);
    const cases = [_]struct {
        argv: []const []const u8,
        delimiter: ?u8 = null,
        border_name: ?border.BorderName = null,
        action: ?Action = null,
        completion: ?CompletionShell = null,
    }{
        .{ .argv = &.{ "--delimiter", ";", "-" }, .delimiter = ';' },
        .{ .argv = &.{ "-d", ";", "-" }, .delimiter = ';' },
        .{ .argv = &.{ "--delimiter", "tab", "-" }, .delimiter = '\t' },
        .{ .argv = &.{ "--delimiter", "\\t", "-" }, .delimiter = '\t' },
        .{ .argv = &.{ "--border", "compact_double", "-" }, .border_name = .compact_double },
        .{ .argv = &.{ "--sort", "score,name", "-" } },
        .{ .argv = &.{ "--completion", "zsh" }, .action = .completion, .completion = .zsh },
        .{ .argv = &.{"--help"}, .action = .help },
        .{ .argv = &.{"--version"}, .action = .version },
    };

    for (cases) |tc| {
        const parsed = try parseTest(tc.argv);
        if (tc.delimiter) |d| try testing.expectEqual(d, parsed.config.delimiter);
        if (tc.border_name) |b| try testing.expectEqual(b, parsed.config.border);
        if (tc.action) |a| try testing.expectEqual(a, parsed.action.?);
        if (tc.completion) |c| try testing.expectEqual(c, parsed.completion.?);
    }
}

test "errorString handles direct mapped errors" {
    var buf: [512]u8 = undefined;
    var diag: clap.Diagnostic = .{};

    try testing.expectEqualStrings("Digits must be between 1 and 6", Args.errorString(&buf, error.InvalidDigits, &diag));
    try testing.expectEqualStrings("Could not read from stdin", Args.errorString(&buf, error.CouldNotReadStdin, &diag));
    try testing.expectEqualStrings("Windows is not yet supported", Args.errorString(&buf, error.Windows, &diag));
    try testing.expectEqualStrings("Error while parsing arguments: OutOfMemory", Args.errorString(&buf, error.OutOfMemory, &diag));
}

test "parse reject cases" {
    const cases = [_]struct {
        argv: []const []const u8,
        err: anyerror,
    }{
        .{ .argv = &.{ "--delimiter", ";;" }, .err = error.InvalidArgument },
        .{ .argv = &.{ "--delimiter", "\x01" }, .err = error.InvalidArgument },
        .{ .argv = &.{ "a.csv", "b.csv" }, .err = error.TooManyArguments },
        .{ .argv = &.{ "--color", "never" }, .err = error.NameNotPartOfEnum },
        .{ .argv = &.{ "--border", "bogus" }, .err = error.NameNotPartOfEnum },
        .{ .argv = &.{ "--digits", "0" }, .err = error.InvalidDigits },
        .{ .argv = &.{ "--digits", "7" }, .err = error.InvalidDigits },
        .{ .argv = &.{ "--head", "1", "--tail", "1" }, .err = error.InvalidHeadTail },
        .{ .argv = &.{ "--head", "0" }, .err = error.InvalidHeadValue },
        .{ .argv = &.{ "--tail", "0" }, .err = error.InvalidTailValue },
    };

    for (cases) |tc| try expectParseError(tc.err, tc.argv);
}

test "errorString reports diagnostics" {
    const cases = [_]struct {
        argv: []const []const u8,
        all_needles: []const []const u8 = &.{},
        any_needles: []const []const u8 = &.{},
    }{
        .{ .argv = &.{"--width"}, .all_needles = &.{"--width"}, .any_needles = &.{ "require", "value" } },
        .{ .argv = &.{ "--color", "bogus" }, .all_needles = &.{"NameNotPartOfEnum"} },
        .{ .argv = &.{ "--digits", "bogus" }, .all_needles = &.{"InvalidCharacter"} },
    };

    for (cases) |tc| {
        const msg = try parseErrorString(tc.argv);
        defer testing.allocator.free(msg);
        for (tc.all_needles) |needle| try testing.expect(std.mem.indexOf(u8, msg, needle) != null);
        if (tc.any_needles.len > 0) {
            var found = false;
            for (tc.any_needles) |needle| found = found or std.mem.indexOf(u8, msg, needle) != null;
            try testing.expect(found);
        }
    }
}

test "resolveInput handles stdin cases" {
    const config: types.Config = .{};

    const banner = try Args.resolveInput(config, 0, &.{}, true);
    try testing.expectEqual(Action.banner, banner.action.?);

    try testing.expectError(error.CouldNotReadStdin, Args.resolveInput(config, 1, &.{}, true));

    const stdin = try Args.resolveInput(config, 1, &.{}, false);
    try testing.expectEqual(null, stdin.action);
    try testing.expectEqual(null, stdin.filename);
}

test "init sets fatal action for parse failures" {
    const out = try Args.init(testing.allocator, &.{"--bogus"});
    defer out.deinit(testing.allocator);
    try testing.expectEqual(Action.fatal, out.action.?);
    try testing.expect(out.err_str != null);
    try testing.expect(std.mem.indexOf(u8, out.err_str.?, "--bogus") != null);
}

test "init keeps enum parse diagnostics" {
    const out = try Args.init(testing.allocator, &.{ "--color", "bogus" });
    defer out.deinit(testing.allocator);
    try testing.expectEqual(Action.fatal, out.action.?);
    try testing.expect(out.err_str != null);
    try testing.expect(std.mem.indexOf(u8, out.err_str.?, "NameNotPartOfEnum") != null);
}

test "init sets fatal action for missing file" {
    const out = try Args.init(testing.allocator, &.{"definitely-not-a-real-file.csv"});
    defer out.deinit(testing.allocator);
    try testing.expectEqual(Action.fatal, out.action.?);
    try testing.expect(out.err_str != null);
    try testing.expect(std.mem.indexOf(u8, out.err_str.?, "definitely-not-a-real-file.csv") != null);
}

fn parseTest(argv: []const []const u8) !Args {
    var diag: clap.Diagnostic = .{};
    return Args.parse(testing.allocator, argv, &diag);
}

fn expectParseError(want: anyerror, argv: []const []const u8) !void {
    var diag: clap.Diagnostic = .{};
    try testing.expectError(want, Args.parse(testing.allocator, argv, &diag));
}

fn parseErrorString(argv: []const []const u8) ![]u8 {
    var buf: [512]u8 = undefined;
    var diag: clap.Diagnostic = .{};
    _ = Args.parse(testing.allocator, argv, &diag) catch |err| return testing.allocator.dupe(u8, Args.errorString(&buf, err, &diag));
    return error.TestUnexpectedResult;
}

const border = @import("border.zig");
const builtin = @import("builtin");
const clap = @import("clap");
const std = @import("std");
const testing = std.testing;
const types = @import("types.zig");
const util = @import("util.zig");
