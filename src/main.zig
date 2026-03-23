// Owns process flow, input detection, loading, and top-level CLI behavior.
pub fn main() !void {
    const code = try main0();
    std.process.exit(code);
}

// Run the CLI and return the process exit code.
fn main0() !u8 {
    // always flush
    defer util.stdout.flush() catch {};
    defer util.stderr.flush() catch {};

    // timer
    var total = try std.time.Timer.start();
    defer util.benchmark("total", total.read());

    // BENCHMARK=1 sanity check
    if (util.hasenv("BENCHMARK") and builtin.mode == .Debug) {
        try util.stderr.writeAll("tennis: BENCHMARK=1 requires `just benchmark` or a release build\n");
        std.process.exit(1);
    }

    // allocators
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer {
        const check = gpa.deinit();
        if (builtin.mode == .Debug) std.debug.assert(check == .ok);
    }
    const alloc = gpa.allocator();

    //
    // args
    //

    var timer = try std.time.Timer.start();
    const argv = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, argv);
    var args = try Args.init(alloc, argv[1..]);
    defer args.deinit(alloc);
    util.benchmark("args", timer.read());

    //
    // handle early exits ("actions")
    //

    if (args.action) |action| {
        switch (action) {
            .banner => try printBanner(null),
            .completion => try completion.write(alloc, args.completion.?),
            .help => try util.stdout.writeAll(Args.help),
            .version => try util.stdout.print("tennis: {s}\n", .{version}),
            .fatal => {
                try printBanner(args.err_str);
                return 1;
            },
        }
        return 0;
    }

    //
    // where are we reading from?
    //

    timer = try std.time.Timer.start();
    var needs_close = false;
    var input = std.fs.File.stdin();
    const filename = args.filename;
    if (filename) |path| {
        if (!std.mem.eql(u8, path, "-")) {
            input = try std.fs.cwd().openFile(path, .{});
            needs_close = true;
        }
    }
    defer if (needs_close) input.close();
    util.benchmark("input", timer.read());

    //
    // read all bytes
    //

    timer = try std.time.Timer.start();
    const input_bytes = try input.readToEndAlloc(alloc, std.math.maxInt(usize));
    defer alloc.free(input_bytes);

    //
    // bytes => data
    //

    const data = load(alloc, &args, input_bytes) catch |err| {
        const err_str = switch (err) {
            error.JaggedCsv => "All csv rows must have same number of columns",
            error.OutOfMemory => return err,
            error.SyntaxError => "That JSON/JSONL file doesn't look right",
            else => "That CSV file doesn't look right",
        };
        try printBanner(err_str);
        return 1;
    };

    //
    // sort
    //

    if (args.config.sort.len > 0) {
        sort.validate(alloc, data.headers(), args.config.sort) catch {
            const maybe_err_str = sort.errorString(alloc, data.headers()) catch null;
            defer if (maybe_err_str) |msg| alloc.free(msg);
            try printBanner(maybe_err_str orelse "That sort doesn't look right");
            return 1;
        };
    }

    //
    // data => table
    //

    const table = try Table.init(alloc, args.config, data);
    defer table.deinit();
    util.benchmark("table.init", timer.read());

    //
    // render
    //

    timer = try std.time.Timer.start();
    try table.renderTable(util.stdout);
    util.benchmark("table.render", timer.read());
    return 0;
}

fn load(alloc: std.mem.Allocator, args: *Args, bytes_in: []const u8) !Data {
    // skip bom
    var bytes = bytes_in;
    if (std.mem.startsWith(u8, bytes, "\xef\xbb\xbf")) {
        bytes = bytes[3..];
    }

    const format = try detect.detectFormat(alloc, args.filename, bytes);
    if (format == .json) {
        return try json.load(alloc, bytes);
    }

    var delimiter = args.config.delimiter;
    if (delimiter == 0) delimiter = sniffer.sniff(bytes) orelse ',';
    return try csv.load(alloc, bytes, delimiter);
}

// Print the startup banner to the shared app writers.
fn printBanner(err_str: ?[]const u8) !void {
    const writer = if (err_str != null) util.stderr else util.stdout;
    if (err_str) |s| {
        try writer.print("tennis: {s}\n", .{s});
    }
    try writer.writeAll("tennis: try 'tennis --help' for more information\n");
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
    _ = @import("float.zig");
    _ = @import("json.zig");
    _ = @import("json_to_string.zig");
    _ = @import("layout.zig");
    _ = @import("natsort.zig");
    _ = @import("render.zig");
    _ = @import("data.zig");
    _ = @import("replay.zig");
    _ = @import("sort.zig");
    _ = @import("sniffer.zig");
    _ = @import("style.zig");
    _ = @import("termbg.zig");
    _ = @import("util.zig");
}

test "load strips UTF-8 BOM before parsing csv and jsonl" {
    const cases = [_]struct {
        args: Args,
        input: []const u8,
        nrows: usize,
        checks: []const struct { row: usize, fields: []const []const u8 },
    }{
        .{
            .args = .{ .filename = null, .config = .{} },
            .input = "\xef\xbb\xbfa,b\nc,d\n",
            .nrows = 2,
            .checks = &.{
                .{ .row = 0, .fields = &.{ "a", "b" } },
                .{ .row = 1, .fields = &.{ "c", "d" } },
            },
        },
        .{
            .args = .{ .filename = "data.jsonl", .config = .{} },
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
        var args = tc.args;
        const data = try load(testing.allocator, &args, tc.input);
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
const json = @import("json.zig");
const sniffer = @import("sniffer.zig");
const sort = @import("sort.zig");
const std = @import("std");
const testing = std.testing;
const Table = @import("table.zig").Table;
const types = @import("types.zig");
const util = @import("util.zig");
const version = @import("build_options").version;
