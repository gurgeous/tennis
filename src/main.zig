//
// main entrypoint
// Owns process flow, input detection, loading, and top-level CLI behavior.
//

pub fn main() !void {
    util.init();
    defer util.deinit();

    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer {
        const check = gpa.deinit();
        if (builtin.mode == .Debug) std.debug.assert(check == .ok);
    }
    const alloc = gpa.allocator();

    var exit: u8 = 0;
    const fatal = main0(alloc) catch |err| switch (err) {
        error.BrokenPipe, error.WriteFailed => null,
        else => return err,
    };
    if (fatal) |value| {
        defer value.deinit(alloc);
        try value.print();
        exit = 1;
    }

    util.stdout.flush() catch {};
    util.stderr.flush() catch {};
    std.process.exit(exit);
}

//
// main0
// Run the CLI and return a printable failure when the command should fail.
//

fn main0(alloc: std.mem.Allocator) !?failure.Failure {
    // timer
    var total = try std.time.Timer.start();
    defer util.benchmark("total", total.read());

    // sanity checks
    if (util.hasenv("BENCHMARK") and builtin.mode == .Debug) {
        return .{ .code = .benchmark_requires_release };
    }

    //
    // parse args
    //

    var timer = try std.time.Timer.start();
    const argv = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, argv);
    var event = try Args.init(alloc, argv[1..]);
    defer event.deinit(alloc);

    //
    // handle early exits ("actions")
    //

    var config = switch (event) {
        .banner => {
            // plain `tennis` with no file/stdin prints the banner
            try failure.printBanner(util.stdout, null);
            return null;
        },
        .completion => |shell| {
            // shell completion is generated immediately
            try completion.write(alloc, shell);
            return null;
        },
        // arg/setup failures are already fully formed Failures
        .fatal => return event.takeFailure(),
        .help => {
            // help text bypasses the rest of the CLI
            try util.stdout.writeAll(Args.help);
            return null;
        },
        .version => {
            // version is another direct early exit
            try util.stdout.print("tennis: {s}\n", .{version});
            return null;
        },
        // otherwise keep the parsed config and continue
        .run => |cfg| blk: {
            event = .banner;
            break :blk cfg;
        },
    };

    //
    // where are we reading from?
    //

    timer = try std.time.Timer.start();
    var input = std.fs.File.stdin();
    var needs_close = false;
    if (config.filename) |path| {
        if (!std.mem.eql(u8, path, "-")) {
            input = try std.fs.cwd().openFile(path, .{});
            needs_close = true;
        }
    }
    defer if (needs_close) input.close();
    util.benchmark("input", timer.read());

    // input => data rows
    var data = load(alloc, config, input) catch |err| {
        if (err == error.SqliteInvalidTable) {
            var db = try sqlite.Sqlite.init(alloc, config.filename.?);
            defer db.deinit();
            return try failure.Failure.fromSqliteTableError(alloc, config.table, db.tables);
        }
        return failure.Failure.fromError(err) orelse return err;
    };

    // plug data headers into config, for validation
    config.bind(alloc, data.headers()) catch |err| {
        const fatal = try failure.Failure.fromTableError(alloc, err, data.headers());
        data.deinit(alloc);
        config.deinit(alloc);
        return fatal;
    };

    //
    // data => table
    //

    // Hand off both config and data here; Table.init owns cleanup from this point on.
    const table = try Table.init(alloc, config, data);
    defer table.deinit();
    util.benchmark("table.init", timer.read());

    //
    // render
    //

    timer = try std.time.Timer.start();
    if (config.pager and builtin.os.tag != .windows and std.fs.File.stdout().isTty()) {
        try renderToPager(alloc, config, table);
    } else {
        try renderToWriter(alloc, config, table, util.stdout);
    }

    util.benchmark("table.render", timer.read());
    return null;
}

//
// loading input data
//

// Load the configured input into table data, dispatching by detected format.
fn load(alloc: std.mem.Allocator, config: types.Config, input: std.fs.File) !Data {
    // typically we read the whole file into memory for processing. That won't
    // work if we are using `sqlite3`, though.
    if (try detect.isSqliteFile(alloc, config.filename, input)) {
        var db = try sqlite.Sqlite.init(alloc, config.filename.?);
        defer db.deinit();
        return try db.load(config.table);
    }

    const bytes = try input.readToEndAlloc(alloc, std.math.maxInt(usize));
    defer alloc.free(bytes);
    return try loadBytes(alloc, config, bytes);
}

// Load in-memory bytes into table data using the existing text format loaders.
fn loadBytes(alloc: std.mem.Allocator, config: types.Config, bytes_in: []const u8) !Data {
    // skip bom
    var bytes = bytes_in;
    if (std.mem.startsWith(u8, bytes, "\xef\xbb\xbf")) {
        bytes = bytes[3..];
    }

    // sqlite3 and stray --table
    const format = try detect.detectFormat(alloc, config.filename, bytes);
    if (format == .sqlite) return error.SqliteRequiresFile;
    if (config.table.len > 0) return error.SqliteTableRequiresSqlite;

    // json
    if (format == .json) return try json.load(alloc, bytes);

    // csv (our default)
    var delimiter = config.delimiter;
    if (delimiter == 0) delimiter = sniffer.sniff(bytes) orelse ',';
    return try csv.load(alloc, bytes, delimiter);
}

//
// rendering
//

fn renderToPager(alloc: std.mem.Allocator, config: types.Config, table: *Table) !void {
    const cmd = (try util.getenv(alloc, "PAGER")) orelse try alloc.dupe(u8, "less");
    defer alloc.free(cmd);
    if (std.mem.eql(u8, cmd, "cat")) return renderToWriter(alloc, config, table, util.stdout);

    var env = try std.process.getEnvMap(alloc);
    defer env.deinit();
    if (env.get("LESS") == null) try env.put("LESS", "FRX");

    var child = std.process.Child.init(&.{ "/bin/sh", "-c", cmd }, alloc);
    child.env_map = &env;
    child.stdin_behavior = .Pipe;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;
    try child.spawn();

    var waited = false;
    defer {
        if (child.stdin) |stdin| stdin.close();
        child.stdin = null;
        if (!waited) _ = child.wait() catch {};
    }

    var buf: [4096]u8 = undefined;
    var out: std.fs.File.Writer = .init(child.stdin.?, &buf);
    try renderToWriter(alloc, config, table, &out.interface);
    try out.interface.flush();
    child.stdin.?.close();
    child.stdin = null;

    _ = try child.wait();
    waited = true;
}

fn renderToWriter(alloc: std.mem.Allocator, config: types.Config, table: *Table, writer: *std.Io.Writer) !void {
    if (config.peek) {
        try peek.render(alloc, table, writer);
    } else {
        try table.renderTable(writer);
    }
}

//
// testing
//

test {
    _ = @import("args.zig");
    _ = @import("border.zig");
    _ = @import("column.zig");
    _ = @import("completion.zig");
    _ = @import("color.zig");
    _ = @import("csv.zig");
    _ = @import("detect.zig");
    _ = @import("doomicode.zig");
    _ = @import("failure.zig");
    _ = @import("float.zig");
    _ = @import("json.zig");
    _ = @import("json_to_string.zig");
    _ = @import("layout.zig");
    _ = @import("natsort.zig");
    _ = @import("peek.zig");
    _ = @import("render.zig");
    _ = @import("sqlite.zig");
    _ = @import("data.zig");
    _ = @import("sort.zig");
    _ = @import("sniffer.zig");
    _ = @import("style.zig");
    _ = @import("termbg.zig");
    _ = @import("util.zig");
}

test "load strips UTF-8 BOM before parsing csv and jsonl" {
    const cases = [_]struct {
        config: types.Config,
        input: []const u8,
        nrows: usize,
        checks: []const struct { row: usize, fields: []const []const u8 },
    }{
        .{
            .config = .{ .filename = null },
            .input = "\xef\xbb\xbfa,b\nc,d\n",
            .nrows = 2,
            .checks = &.{
                .{ .row = 0, .fields = &.{ "a", "b" } },
                .{ .row = 1, .fields = &.{ "c", "d" } },
            },
        },
        .{
            .config = .{ .filename = "data.jsonl" },
            .input = "\xef\xbb\xbf{\"name\":\"alice\"}\r\n{\"name\":\"bob\"}",
            .nrows = 3,
            .checks = &.{
                .{ .row = 0, .fields = &.{"name"} },
                .{ .row = 1, .fields = &.{"alice"} },
                .{ .row = 2, .fields = &.{"bob"} },
            },
        },
    };

    for (cases) |tc| {
        const bytes = try testing.allocator.dupe(u8, tc.input);
        defer testing.allocator.free(bytes);
        const data = try loadBytes(testing.allocator, tc.config, bytes);
        defer data.deinit(testing.allocator);

        try testing.expectEqual(tc.nrows, data.rows.len);
        for (tc.checks) |check| {
            try testing.expectEqual(check.fields.len, data.row(check.row).len);
            for (check.fields, data.row(check.row)) |want, got| try testing.expectEqualStrings(want, got);
        }
    }
}

const Args = @import("args.zig").Args;
const builtin = @import("builtin");
const completion = @import("completion.zig");
const csv = @import("csv.zig");
const Data = @import("data.zig").Data;
const detect = @import("detect.zig");
const failure = @import("failure.zig");
const json = @import("json.zig");
const peek = @import("peek.zig");
const sniffer = @import("sniffer.zig");
const sqlite = @import("sqlite.zig");
const std = @import("std");
const Table = @import("table.zig").Table;
const testing = std.testing;
const types = @import("types.zig");
const util = @import("util.zig");
const version = @import("build_options").version;
