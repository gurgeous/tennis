//
// parse cli args into an Args struct
//

// CLI parsing and help text for the app entry point.
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
        .SHELL = clap.parsers.enumeration(types.CompletionShell),
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

    // Parse argv into one top-level main event.
    pub fn init(alloc: std.mem.Allocator, argv: []const []const u8) !types.MainEvent {
        var diagnostics: clap.Diagnostic = .{};
        const event = parse(alloc, argv, &diagnostics) catch |err| {
            return .{ .fatal = try failure.Failure.fromClapError(alloc, err, &diagnostics) };
        };

        // quick check of file here
        if (event == .run) {
            if (event.run.filename) |filename| {
                if (!std.mem.eql(u8, filename, "-") and !util.fileExists(filename)) {
                    return .{ .fatal = try failure.Failure.fromFileNotFound(alloc, filename) };
                }
            }
        }

        return event;
    }

    // Parse argv and map supported flags into config.
    fn parse(
        alloc: std.mem.Allocator,
        argv: []const []const u8,
        diagnostic: *clap.Diagnostic,
    ) anyerror!types.MainEvent {
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

        if (res.args.help > 0) return .help;
        if (res.args.completion) |shell| return .{ .completion = shell };
        if (res.args.version > 0) return .version;

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

    // Resolve positional input into stdin, file, or banner behavior.
    fn resolveInput(
        config: types.Config,
        argv_len: usize,
        files: []const []const u8,
        stdin_is_tty: bool,
    ) !types.MainEvent {
        switch (files.len) {
            0 => {
                if (stdin_is_tty) {
                    if (argv_len != 0) return error.CouldNotReadStdin;
                    return .banner;
                }
                return .{ .run = config };
            },
            1 => {
                var out = config;
                out.filename = files[0];
                return .{ .run = out };
            },
            else => return error.TooManyArguments,
        }
    }
};

//
// testing
//

test "parse args accepts dash positional" {
    const out = try Args.init(testing.allocator, &.{"-"});
    try testing.expect(out == .run);
    try testing.expectEqualStrings("-", out.run.filename.?);
}

test "parse option config case" {
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

    try testing.expect(out == .run);
    try testing.expectEqual(border.BorderName.double, out.run.border);
    try testing.expectEqual(types.Color.off, out.run.color);
    try testing.expectEqual(@as(usize, 4), out.run.digits);
    try testing.expectEqual(@as(usize, 5), out.run.head);
    try testing.expect(out.run.reverse);
    try testing.expectEqualStrings("name,score", out.run.select);
    try testing.expectEqualStrings("score,name", out.run.sort);
    try testing.expectEqual(types.Theme.light, out.run.theme);
    try testing.expectEqualStrings("foo", out.run.title);
    try testing.expect(out.run.vanilla);
    try testing.expectEqual(80, out.run.width);
    try testing.expect(out.run.row_numbers);
    try testing.expectEqualStrings("-", out.run.filename.?);
}

test "parse option event cases" {
    const cases = [_]struct {
        argv: []const []const u8,
        delimiter: ?u8 = null,
        border_name: ?border.BorderName = null,
        event: ?types.MainEvent = null,
    }{
        .{ .argv = &.{ "--delimiter", ";", "-" }, .delimiter = ';' },
        .{ .argv = &.{ "-d", ";", "-" }, .delimiter = ';' },
        .{ .argv = &.{ "--delimiter", "tab", "-" }, .delimiter = '\t' },
        .{ .argv = &.{ "--delimiter", "\\t", "-" }, .delimiter = '\t' },
        .{ .argv = &.{ "--border", "compact_double", "-" }, .border_name = .compact_double },
        .{ .argv = &.{ "--sort", "score,name", "-" } },
        .{ .argv = &.{ "--completion", "zsh" }, .event = .{ .completion = .zsh } },
        .{ .argv = &.{"--help"}, .event = .help },
        .{ .argv = &.{"--version"}, .event = .version },
    };

    for (cases) |tc| {
        const parsed = try parseTest(tc.argv);
        if (tc.delimiter) |d| try testing.expectEqual(d, parsed.run.delimiter);
        if (tc.border_name) |b| try testing.expectEqual(b, parsed.run.border);
        if (tc.event) |event| try testing.expectEqual(event, parsed);
    }
}

test "fromClapError handles direct mapped errors" {
    const cases = [_]struct {
        err: anyerror,
        want: failure.FailureCode,
    }{
        .{ .err = error.InvalidDigits, .want = .invalid_digits },
        .{ .err = error.CouldNotReadStdin, .want = .could_not_read_stdin },
        .{ .err = error.Windows, .want = .windows },
    };

    for (cases) |tc| {
        var diag: clap.Diagnostic = .{};
        const fatal = try failure.Failure.fromClapError(testing.allocator, tc.err, &diag);
        defer fatal.deinit(testing.allocator);
        try testing.expectEqual(tc.want, fatal.code);
    }
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

test "fromClapError keeps clap diagnostics" {
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
    try testing.expectEqual(types.MainEvent.banner, banner);

    try testing.expectError(error.CouldNotReadStdin, Args.resolveInput(config, 1, &.{}, true));

    const stdin = try Args.resolveInput(config, 1, &.{}, false);
    try testing.expect(stdin == .run);
    try testing.expectEqual(null, stdin.run.filename);
}

test "init returns fatal event for parse failures" {
    const out = try Args.init(testing.allocator, &.{"--bogus"});
    defer out.deinit(testing.allocator);
    try testing.expect(out == .fatal);
    const msg = try failure.string(testing.allocator, out.fatal);
    defer testing.allocator.free(msg);
    try testing.expect(std.mem.indexOf(u8, msg, "--bogus") != null);
}

test "init keeps enum parse diagnostics" {
    const out = try Args.init(testing.allocator, &.{ "--color", "bogus" });
    defer out.deinit(testing.allocator);
    try testing.expect(out == .fatal);
    const msg = try failure.string(testing.allocator, out.fatal);
    defer testing.allocator.free(msg);
    try testing.expect(std.mem.indexOf(u8, msg, "NameNotPartOfEnum") != null);
}

test "init returns fatal event for missing file" {
    const out = try Args.init(testing.allocator, &.{"definitely-not-a-real-file.csv"});
    defer out.deinit(testing.allocator);
    try testing.expect(out == .fatal);
    const msg = try failure.string(testing.allocator, out.fatal);
    defer testing.allocator.free(msg);
    try testing.expect(std.mem.indexOf(u8, msg, "definitely-not-a-real-file.csv") != null);
}

fn parseTest(argv: []const []const u8) !types.MainEvent {
    var diag: clap.Diagnostic = .{};
    return Args.parse(testing.allocator, argv, &diag);
}

fn expectParseError(want: anyerror, argv: []const []const u8) !void {
    var diag: clap.Diagnostic = .{};
    try testing.expectError(want, Args.parse(testing.allocator, argv, &diag));
}

fn parseErrorString(argv: []const []const u8) ![]u8 {
    var diag: clap.Diagnostic = .{};
    _ = Args.parse(testing.allocator, argv, &diag) catch |err| {
        const fatal = try failure.Failure.fromClapError(testing.allocator, err, &diag);
        defer fatal.deinit(testing.allocator);
        return failure.string(testing.allocator, fatal);
    };
    return error.TestUnexpectedResult;
}

const border = @import("border.zig");
const builtin = @import("builtin");
const clap = @import("clap");
const failure = @import("failure.zig");
const std = @import("std");
const testing = std.testing;
const types = @import("types.zig");
const util = @import("util.zig");
