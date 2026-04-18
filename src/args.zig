//
// parse cli args into an Args struct
//

// CLI parsing and help text for the app entry point.
pub const Args = struct {
    pub const help =
        \\ Usage: tennis [options...] <file.csv>
        \\        also supports stdin, json/jsonl, sqlite, etc.
        \\
        \\ Popular options:
        \\  -n, --row-numbers          Turn on row numbers
        \\  -t, --title <string>       Add a title to the table
        \\      --border <border>      Table border style (rounded|thin|double|...)
        \\  -p, --pager                Send output through $PAGER or less
        \\      --peek                 Show csv shape, sample, and handy stats
        \\      --zebra                Turn on zebra stripes
        \\
        \\ Sort, filter, etc:
        \\      --deselect <headers>   De-select comma-separated headers
        \\      --select <headers>     Select or reorder comma-separated headers
        \\      --sort <headers>       Sort rows by comma-separated headers
        \\  -r, --reverse              Reverse rows (helpful for sorting)
        \\      --shuffle, --shuf      Shuffle rows into random order
        \\      --head <int>           Show first N rows
        \\      --tail <int>           Show last N rows
        \\      --filter <string>      Only show rows that contain this text
        \\
        \\ Other options:
        \\      --color <color>        Turn color off and on (on|off|auto)
        \\      --delimiter <char>     Set CSV delim (can be any char or "tab")
        \\      --digits <int>         Digits after decimal for float columns
        \\      --table <table>        Select the db table (for sqlite)
        \\      --theme <theme>        Select color theme (auto|dark|light)
        \\      --vanilla              Disable numeric formatting
        \\      --width <width>        Set table width, or try (min|max)
        \\
        \\      --completion <shell>   Print shell completion (bash|zsh)
        \\      --help                 Get help
        \\      --version              Show version number and exit
        \\
    ;

    const params = clap.parseParamsComptime(
        \\    --border <BORDER>
        \\    --color <COLOR>
        \\    --completion <SHELL>
        \\    --deselect <STRING>
        \\    --digits <INT>
        \\    --filter <STRING>
        \\    --head <INT>
        \\-p, --pager
        \\    --peek
        \\    --select <STRING>
        \\    --shuf
        \\    --shuffle
        \\    --sort <STRING>
        \\    --table <STRING>
        \\    --tail <INT>
        \\    --theme <THEME>
        \\    --vanilla
        \\    --width <WIDTH>
        \\-d, --delimiter <CHAR>
        \\-h, --help
        \\-n, --row-numbers
        \\-r, --reverse
        \\-t, --title <STRING>
        \\-v, --version
        \\-z, --zebra
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
        .WIDTH = parseWidth,
    };

    // Parse a delimiter argument into one ASCII byte.
    fn parseChar(input: []const u8) error{InvalidArgument}!u8 {
        if (input.len == 1 and std.ascii.isPrint(input[0]) and input[0] < 0x7f) return input[0];
        if (std.mem.eql(u8, input, "tab")) return '\t';
        if (std.mem.eql(u8, input, "\\t")) return '\t';
        return error.InvalidArgument;
    }

    // Parse one width mode argument.
    fn parseWidth(input: []const u8) error{InvalidArgument}!types.Width {
        if (std.mem.eql(u8, input, "min")) return .min;
        if (std.mem.eql(u8, input, "max")) return .max;
        const value = std.fmt.parseInt(usize, input, 10) catch return error.InvalidArgument;
        // 0 works but is undocumented, this is fine
        if (value == 0) return .auto;
        return .{ .chars = value };
    }

    // Parse argv into one top-level main event.
    pub fn init(app: *const App, argv: []const []const u8) !MainEvent {
        var diagnostics: clap.Diagnostic = .{};
        const event = parse(app, argv, &diagnostics) catch |err| {
            return .{ .fatal = try failure.Failure.fromClapError(app.alloc, err, &diagnostics) };
        };

        // quick check of file here
        if (event == .run) {
            if (event.run.filename) |filename| {
                if (!std.mem.eql(u8, filename, "-") and !util.fileExists(app.io, filename)) {
                    return .{ .fatal = try failure.Failure.fromFileNotFound(app.alloc, filename) };
                }
            }
        }

        return event;
    }

    // Parse process args into one top-level main event.
    pub fn initProcessArgs(app: *const App, process_args: std.process.Args) !MainEvent {
        // std.process.Args.toSlice requires arena-style allocation because the
        // returned argv may reference multiple allocations depending on platform.
        var arena = std.heap.ArenaAllocator.init(app.alloc);
        defer arena.deinit();
        const argv = try process_args.toSlice(arena.allocator());
        return init(app, argv[1..]);
    }

    // Parse argv and map supported flags into config.
    fn parse(app: *const App, argv: []const []const u8, diag: *clap.Diagnostic) !MainEvent {
        var iter = clap.args.SliceIterator{ .args = argv };
        var res = try clap.parseEx(clap.Help, &params, parsers, &iter, .{
            .allocator = app.alloc,
            .diagnostic = diag,
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

        var config: Config = .{};
        if (res.args.border) |v| config.border = v;
        if (res.args.color) |v| config.color = v;
        if (res.args.deselect) |v| config.deselect = v;
        config.delimiter = if (res.args.delimiter) |v| v else 0;
        if (res.args.filter) |v| config.filter = v;
        config.pager = res.args.pager > 0;
        config.peek = res.args.peek > 0;
        config.reverse = res.args.reverse > 0;
        config.row_numbers = @field(res.args, "row-numbers") > 0;
        if (res.args.select) |v| config.select = v;
        config.shuffle = res.args.shuffle > 0 or res.args.shuf > 0;
        if (res.args.sort) |v| config.sort = v;
        if (res.args.table) |v| config.table = v;
        if (res.args.theme) |v| config.theme = v;
        if (res.args.title) |v| config.title = try app.alloc.dupe(u8, v);
        config.vanilla = res.args.vanilla > 0;
        if (res.args.width) |v| config.width = v;
        config.zebra = res.args.zebra > 0;
        if (res.args.digits) |v| {
            config.digits = v;
            if (v < 1 or v > 6) return error.InvalidDigits;
        }
        if (res.args.head) |v| {
            config.head = v;
            if (v == 0) return error.InvalidHeadValue;
        }
        if (res.args.tail) |v| {
            config.tail = v;
            if (v == 0) return error.InvalidTailValue;
            if (config.head > 0) return error.InvalidHeadTail;
        }

        //
        // now handle filename
        //

        return try resolveInput(config, argv.len, res.positionals[0], std.Io.File.stdin().isTty(app.io) catch false);
    }

    // Resolve positional input into stdin, file, or banner behavior.
    fn resolveInput(
        config: Config,
        argv_len: usize,
        files: []const []const u8,
        stdin_is_tty: bool,
    ) !MainEvent {
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
    const app = try App.testInit(testing.allocator);
    defer app.destroy();
    const out = try Args.init(app, &.{"-"});
    try testing.expect(out == .run);
    try testing.expectEqualStrings("-", out.run.filename.?);
}

test "parse option config case" {
    var out = try parseTest(&.{
        "--border",
        "double",
        "--color",
        "off",
        "--digits",
        "4",
        "--filter",
        "ali",
        "--deselect",
        "city,tags",
        "--head",
        "5",
        "-p",
        "--peek",
        "--reverse",
        "--zebra",
        "--shuffle",
        "--select",
        "name,score",
        "--sort",
        "score,name",
        "--table",
        "players",
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
    defer out.deinit(testing.allocator);

    try testing.expect(out == .run);
    try testing.expectEqual(border.BorderName.double, out.run.border);
    try testing.expectEqual(types.Color.off, out.run.color);
    try testing.expectEqualStrings("city,tags", out.run.deselect);
    try testing.expectEqual(@as(usize, 4), out.run.digits);
    try testing.expectEqualStrings("ali", out.run.filter);
    try testing.expectEqual(@as(usize, 5), out.run.head);
    try testing.expect(out.run.pager);
    try testing.expect(out.run.peek);
    try testing.expect(out.run.reverse);
    try testing.expect(out.run.zebra);
    try testing.expect(out.run.shuffle);
    try testing.expectEqualStrings("name,score", out.run.select);
    try testing.expectEqualStrings("score,name", out.run.sort);
    try testing.expectEqualStrings("players", out.run.table);
    try testing.expectEqual(types.Theme.light, out.run.theme);
    try testing.expectEqualStrings("foo", out.run.title);
    try testing.expect(out.run.vanilla);
    try testing.expectEqual(types.Width{ .chars = 80 }, out.run.width);
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
        .{ .argv = &.{ "--delimiter", "tab", "-" }, .delimiter = '\t' },
        .{ .argv = &.{ "--delimiter", "\\t", "-" }, .delimiter = '\t' },
        .{ .argv = &.{ "--border", "compact_double", "-" }, .border_name = .compact_double },
        .{ .argv = &.{ "--filter", "ali", "-" } },
        .{ .argv = &.{ "--deselect", "score,name", "-" } },
        .{ .argv = &.{ "--pager", "-" } },
        .{ .argv = &.{ "-p", "-" } },
        .{ .argv = &.{ "--peek", "-" } },
        .{ .argv = &.{ "--zebra", "-" } },
        .{ .argv = &.{ "--shuffle", "-" } },
        .{ .argv = &.{ "--shuf", "-" } },
        .{ .argv = &.{ "--sort", "score,name", "-" } },
        .{ .argv = &.{ "--table", "players", "-" } },
        .{ .argv = &.{ "--width", "min", "-" } },
        .{ .argv = &.{ "--width", "max", "-" } },
        .{ .argv = &.{ "--width", "80", "-" } },
        .{ .argv = &.{ "--completion", "zsh" }, .event = .{ .completion = .zsh } },
        .{ .argv = &.{"--help"}, .event = .help },
        .{ .argv = &.{"--version"}, .event = .version },
    };

    for (cases) |tc| {
        var parsed = try parseTest(tc.argv);
        defer parsed.deinit(testing.allocator);
        if (tc.delimiter) |d| try testing.expectEqual(d, parsed.run.delimiter);
        if (tc.border_name) |b| try testing.expectEqual(b, parsed.run.border);
        if (std.mem.eql(u8, tc.argv[0], "--deselect")) try testing.expectEqualStrings("score,name", parsed.run.deselect);
        if (std.mem.eql(u8, tc.argv[0], "--filter")) try testing.expectEqualStrings("ali", parsed.run.filter);
        if (std.mem.eql(u8, tc.argv[0], "--pager") or std.mem.eql(u8, tc.argv[0], "-p")) try testing.expect(parsed.run.pager);
        if (std.mem.eql(u8, tc.argv[0], "--peek")) try testing.expect(parsed.run.peek);
        if (std.mem.eql(u8, tc.argv[0], "--shuffle") or std.mem.eql(u8, tc.argv[0], "--shuf")) {
            try testing.expect(parsed.run.shuffle);
        }
        if (std.mem.eql(u8, tc.argv[0], "--table")) try testing.expectEqualStrings("players", parsed.run.table);
        if (std.mem.eql(u8, tc.argv[0], "--width") and std.mem.eql(u8, tc.argv[1], "min")) try testing.expectEqual(types.Width.min, parsed.run.width);
        if (std.mem.eql(u8, tc.argv[0], "--width") and std.mem.eql(u8, tc.argv[1], "max")) try testing.expectEqual(types.Width.max, parsed.run.width);
        if (std.mem.eql(u8, tc.argv[0], "--width") and std.mem.eql(u8, tc.argv[1], "80")) try testing.expectEqual(types.Width{ .chars = 80 }, parsed.run.width);
        if (std.mem.eql(u8, tc.argv[0], "--zebra")) try testing.expect(parsed.run.zebra);
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
        .{ .argv = &.{ "--width", "bogus" }, .err = error.InvalidArgument },
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
    const app = try App.testInit(testing.allocator);
    defer app.destroy();
    const out = try Args.init(app, &.{"--bogus"});
    defer out.deinit(testing.allocator);
    try testing.expect(out == .fatal);
    const msg = try failure.string(testing.allocator, out.fatal);
    defer testing.allocator.free(msg);
    try testing.expect(std.mem.indexOf(u8, msg, "--bogus") != null);
}

test "init keeps enum parse diagnostics" {
    const app = try App.testInit(testing.allocator);
    defer app.destroy();
    const out = try Args.init(app, &.{ "--color", "bogus" });
    defer out.deinit(testing.allocator);
    try testing.expect(out == .fatal);
    const msg = try failure.string(testing.allocator, out.fatal);
    defer testing.allocator.free(msg);
    try testing.expect(std.mem.indexOf(u8, msg, "NameNotPartOfEnum") != null);
}

test "init returns fatal event for missing file" {
    const app = try App.testInit(testing.allocator);
    defer app.destroy();
    const out = try Args.init(app, &.{"definitely-not-a-real-file.csv"});
    defer out.deinit(testing.allocator);
    try testing.expect(out == .fatal);
    const msg = try failure.string(testing.allocator, out.fatal);
    defer testing.allocator.free(msg);
    try testing.expect(std.mem.indexOf(u8, msg, "definitely-not-a-real-file.csv") != null);
}

fn parseTest(argv: []const []const u8) !MainEvent {
    const app = try App.testInit(testing.allocator);
    defer app.destroy();
    var diag: clap.Diagnostic = .{};
    return Args.parse(app, argv, &diag);
}

fn expectParseError(want: anyerror, argv: []const []const u8) !void {
    const app = try App.testInit(testing.allocator);
    defer app.destroy();
    var diag: clap.Diagnostic = .{};
    try testing.expectError(want, Args.parse(app, argv, &diag));
}

fn parseErrorString(argv: []const []const u8) ![]u8 {
    const app = try App.testInit(testing.allocator);
    defer app.destroy();
    var diag: clap.Diagnostic = .{};
    _ = Args.parse(app, argv, &diag) catch |err| {
        const fatal = try failure.Failure.fromClapError(testing.allocator, err, &diag);
        defer fatal.deinit(testing.allocator);
        return failure.string(testing.allocator, fatal);
    };
    return error.TestUnexpectedResult;
}

const App = @import("app.zig").App;
const border = @import("border.zig");
const builtin = @import("builtin");
const clap = @import("clap");
const failure = @import("failure.zig");
const std = @import("std");
const testing = std.testing;
const types = @import("types.zig");
const util = @import("util.zig");
const Config = types.Config;
const MainEvent = types.MainEvent;
