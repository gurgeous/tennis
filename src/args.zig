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

    // Parse process args into owned CLI config.
    pub fn init(app: *const App, process_args: std.process.Args, diagnostics: *Diagnostics) !Config {
        // std.process.Args.toSlice requires arena-style allocation because the
        // returned argv may reference multiple allocations depending on
        // platform. First thing we do is create a dup, but be careful with it.
        var arena = std.heap.ArenaAllocator.init(app.alloc);
        defer arena.deinit();
        const unowned_argv = try process_args.toSlice(arena.allocator());
        const argv = try util.deepDupe(u8, app.alloc, unowned_argv[1..]);
        var handed_off = false;
        errdefer if (!handed_off) util.deepFree(u8, app.alloc, argv);

        var config = try parse(app, argv, diagnostics);
        handed_off = true;

        // quick check of file here
        if (config.filename) |filename| {
            if (!std.mem.eql(u8, filename, "-") and !util.fileExists(app.io, filename)) {
                config.deinit(app.alloc);
                return error.FileNotFound;
            }
        }

        return config;
    }

    // Parse owned argv and hand it to Config when producing a run event.
    fn parse(app: *const App, argv: []const []const u8, diagnostics: *Diagnostics) !Config {
        var config: Config = .{ .argv = argv };
        var iter = clap.args.SliceIterator{ .args = config.argv };
        var clap_diag: clap.Diagnostic = .{};
        var res = clap.parseEx(clap.Help, &params, parsers, &iter, .{
            .allocator = app.alloc,
            .diagnostic = &clap_diag,
        }) catch |err| {
            try diagnostics.report(app.alloc, err, clap_diag);
            return err;
        };
        defer res.deinit();

        //
        // these are early exits
        //

        config.completion = res.args.completion;
        config.help = res.args.help > 0;
        config.version = res.args.version > 0;
        if (config.help or config.completion != null or config.version) return config;

        //
        // copy args into Config
        //

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
        if (res.args.title) |v| config.title = try app.alloc.dupe(u8, v);
        errdefer if (config.title.len > 0) app.alloc.free(config.title);

        switch (res.positionals[0].len) {
            0 => if (util.isTty(app.io, std.Io.File.stdin()) and argv.len != 0) return error.CouldNotReadStdin,
            1 => config.filename = res.positionals[0][0],
            else => return error.TooManyArguments,
        }

        return config;
    }

    // Our diagnostics from parse
    pub const Diagnostics = struct {
        const Self = @This();

        detail: []const u8 = "",

        // Render and own clap's diagnostic message.
        pub fn report(self: *Self, alloc: std.mem.Allocator, err: anyerror, diag: clap.Diagnostic) !void {
            var buf: [512]u8 = undefined;
            var writer = std.Io.Writer.fixed(&buf);
            diag.report(&writer, err) catch {};

            const msg = util.strip(u8, writer.buffered());
            self.detail = if (msg.len > 0)
                try alloc.dupe(u8, msg)
            else
                try std.fmt.allocPrint(alloc, "Error while parsing arguments: {s}", .{@errorName(err)});
        }

        // Release any rendered diagnostic message.
        pub fn deinit(self: Self, alloc: std.mem.Allocator) void {
            alloc.free(self.detail);
        }
    };
};

//
// testing
//

test "parse args accepts dash positional" {
    const out = try parseTest(&.{"-"});
    defer out.deinit(testing.allocator);
    try testing.expectEqualStrings("-", out.filename.?);
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

    try testing.expectEqual(border.BorderName.double, out.border);
    try testing.expectEqual(types.Color.off, out.color);
    try testing.expectEqualStrings("city,tags", out.deselect);
    try testing.expectEqual(@as(usize, 4), out.digits);
    try testing.expectEqualStrings("ali", out.filter);
    try testing.expectEqual(@as(usize, 5), out.head);
    try testing.expect(out.pager);
    try testing.expect(out.peek);
    try testing.expect(out.reverse);
    try testing.expect(out.zebra);
    try testing.expect(out.shuffle);
    try testing.expectEqualStrings("name,score", out.select);
    try testing.expectEqualStrings("score,name", out.sort);
    try testing.expectEqualStrings("players", out.table);
    try testing.expectEqual(types.Theme.light, out.theme);
    try testing.expectEqualStrings("foo", out.title);
    try testing.expect(out.vanilla);
    try testing.expectEqual(types.Width{ .chars = 80 }, out.width);
    try testing.expect(out.row_numbers);
    try testing.expectEqualStrings("-", out.filename.?);
}

test "parse option cases" {
    const cases = [_]struct {
        argv: []const []const u8,
        delimiter: ?u8 = null,
        border_name: ?border.BorderName = null,
        completion: ?types.CompletionShell = null,
        help: bool = false,
        version: bool = false,
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
        .{ .argv = &.{ "--completion", "zsh" }, .completion = .zsh },
        .{ .argv = &.{"--help"}, .help = true },
        .{ .argv = &.{"--version"}, .version = true },
    };

    for (cases) |tc| {
        var parsed = try parseTest(tc.argv);
        defer parsed.deinit(testing.allocator);
        if (tc.delimiter) |d| try testing.expectEqual(d, parsed.delimiter);
        if (tc.border_name) |b| try testing.expectEqual(b, parsed.border);
        if (std.mem.eql(u8, tc.argv[0], "--deselect")) try testing.expectEqualStrings("score,name", parsed.deselect);
        if (std.mem.eql(u8, tc.argv[0], "--filter")) try testing.expectEqualStrings("ali", parsed.filter);
        if (std.mem.eql(u8, tc.argv[0], "--pager") or std.mem.eql(u8, tc.argv[0], "-p")) try testing.expect(parsed.pager);
        if (std.mem.eql(u8, tc.argv[0], "--peek")) try testing.expect(parsed.peek);
        if (std.mem.eql(u8, tc.argv[0], "--shuffle") or std.mem.eql(u8, tc.argv[0], "--shuf")) {
            try testing.expect(parsed.shuffle);
        }
        if (std.mem.eql(u8, tc.argv[0], "--table")) try testing.expectEqualStrings("players", parsed.table);
        if (std.mem.eql(u8, tc.argv[0], "--width") and std.mem.eql(u8, tc.argv[1], "min")) try testing.expectEqual(types.Width.min, parsed.width);
        if (std.mem.eql(u8, tc.argv[0], "--width") and std.mem.eql(u8, tc.argv[1], "max")) try testing.expectEqual(types.Width.max, parsed.width);
        if (std.mem.eql(u8, tc.argv[0], "--width") and std.mem.eql(u8, tc.argv[1], "80")) try testing.expectEqual(types.Width{ .chars = 80 }, parsed.width);
        if (std.mem.eql(u8, tc.argv[0], "--zebra")) try testing.expect(parsed.zebra);
        if (tc.completion) |shell| try testing.expectEqual(shell, parsed.completion.?);
        try testing.expectEqual(tc.help, parsed.help);
        try testing.expectEqual(tc.version, parsed.version);
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

test "init returns diagnostics for parse failures" {
    const msg = try parseErrorString(&.{"--bogus"});
    defer testing.allocator.free(msg);
    try testing.expect(std.mem.indexOf(u8, msg, "--bogus") != null);
}

test "init keeps enum parse diagnostics" {
    const msg = try parseErrorString(&.{ "--color", "bogus" });
    defer testing.allocator.free(msg);
    try testing.expect(std.mem.indexOf(u8, msg, "NameNotPartOfEnum") != null);
}

test "init rejects missing files" {
    try testing.expectError(error.FileNotFound, initTest(&.{"definitely-not-a-real-file.csv"}));
}

fn parseTest(unowned_argv: []const []const u8) !Config {
    const app = try App.testInit(testing.allocator);
    defer app.destroy();
    const argv = try util.deepDupe(u8, testing.allocator, unowned_argv);
    errdefer util.deepFree(u8, testing.allocator, argv);
    var diagnostics: Args.Diagnostics = .{};
    defer diagnostics.deinit(testing.allocator);
    return Args.parse(app, argv, &diagnostics);
}

fn expectParseError(want: anyerror, unowned_argv: []const []const u8) !void {
    const app = try App.testInit(testing.allocator);
    defer app.destroy();
    const argv = try util.deepDupe(u8, testing.allocator, unowned_argv);
    defer util.deepFree(u8, testing.allocator, argv);
    var diagnostics: Args.Diagnostics = .{};
    defer diagnostics.deinit(testing.allocator);
    try testing.expectError(want, Args.parse(app, argv, &diagnostics));
}

fn parseErrorString(argv: []const []const u8) ![]u8 {
    const app = try App.testInit(testing.allocator);
    defer app.destroy();
    var diagnostics: Args.Diagnostics = .{};
    defer diagnostics.deinit(testing.allocator);
    var config = initTestWithDiagnostics(app, argv, &diagnostics) catch |err| return parseErrorToString(err, diagnostics.detail);
    config.deinit(testing.allocator);
    return error.TestUnexpectedResult;
}

fn parseErrorToString(err: anyerror, detail: []const u8) ![]u8 {
    const fatal = try failure.Failure.fromArgsError(testing.allocator, err, detail);
    defer fatal.deinit(testing.allocator);
    return failure.string(testing.allocator, fatal);
}

fn initTest(unowned_argv: []const []const u8) !Config {
    const app = try App.testInit(testing.allocator);
    defer app.destroy();
    var diagnostics: Args.Diagnostics = .{};
    defer diagnostics.deinit(testing.allocator);
    return try initTestWithDiagnostics(app, unowned_argv, &diagnostics);
}

fn initTestWithDiagnostics(app: *const App, unowned_argv: []const []const u8, diagnostics: *Args.Diagnostics) !Config {
    const argv = try util.deepDupe(u8, testing.allocator, unowned_argv);
    var handed_off = false;
    errdefer if (!handed_off) util.deepFree(u8, testing.allocator, argv);

    var config = try Args.parse(app, argv, diagnostics);
    handed_off = true;

    if (config.filename) |filename| {
        if (!std.mem.eql(u8, filename, "-") and !util.fileExists(app.io, filename)) {
            config.deinit(testing.allocator);
            return error.FileNotFound;
        }
    }

    return config;
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
