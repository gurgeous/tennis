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
    const args = try Args.init(alloc, argv[1..]);
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

    const data = load(alloc, args, input_bytes) catch |err| {
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
        validateSort(headersOf(data), args.config.sort) catch |err| {
            const maybe_err_str = sortErrorString(alloc, headersOf(data), args.config.sort, err) catch null;
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

    const format = try detect.detectFormat(alloc, args.config.filename, bytes);
    if (format == .json) {
        return try json.load(alloc, bytes);
    }

    var delimiter = args.config.delimiter;
    if (delimiter == 0) delimiter = sniffer.sniff(bytes) orelse ',';
    return try csv.load(alloc, bytes, delimiter);
}

fn headersOf(data: Data) []const []const u8 {
    return if (data.rows.len > 0) data.row(0) else &.{};
}

fn validateSort(headers: []const []const u8, spec: []const u8) !void {
    if (Table.firstInvalidSortColumn(headers, spec)) |bad| {
        if (util.strip(u8, bad).len == 0) {
            return error.InvalidSortSpec;
        }
        return error.InvalidSortColumn;
    }
}

fn sortErrorString(alloc: std.mem.Allocator, headers: []const []const u8, spec: []const u8, err: anyerror) ![]u8 {
    var columns: std.ArrayList(u8) = .empty;
    defer columns.deinit(alloc);
    for (headers, 0..) |header, ii| {
        if (ii > 0) try columns.appendSlice(alloc, ", ");
        try columns.appendSlice(alloc, header);
    }

    return switch (err) {
        error.InvalidSortSpec => std.fmt.allocPrint(alloc, "Invalid sort spec '{s}'. Empty sort columns are not allowed. Columns: {s}", .{ spec, columns.items }),
        error.InvalidSortColumn => blk: {
            const bad = Table.firstInvalidSortColumn(headers, spec) orelse unreachable;
            break :blk std.fmt.allocPrint(alloc, "Unknown sort column '{s}'. Columns: {s}", .{ util.strip(u8, bad), columns.items });
        },
        else => unreachable,
    };
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
    _ = @import("render.zig");
    _ = @import("data.zig");
    _ = @import("replay.zig");
    _ = @import("sniffer.zig");
    _ = @import("style.zig");
    _ = @import("termbg.zig");
    _ = @import("util.zig");
}

// test "initTable strips UTF-8 BOM before CSV parsing" {
//     const table = try initTable(testing.allocator, null, .{}, "\xef\xbb\xbfa,b\nc,d\n");
//     defer table.deinit();

//     try testing.expectEqualStrings("a", table.headers()[0]);
//     try testing.expectEqualStrings("b", table.headers()[1]);
//     try testing.expectEqualStrings("c", table.row(0)[0]);
//     try testing.expectEqualStrings("d", table.row(0)[1]);
// }

// test "initTable strips UTF-8 BOM before JSONL parsing" {
//     const table = try initTable(
//         testing.allocator,
//         "data.jsonl",
//         .{},
//         "\xef\xbb\xbf{\"name\":\"alice\"}\r\n{\"name\":\"bob\"}",
//     );
//     defer table.deinit();

//     try testing.expectEqual(@as(usize, 2), table.nrows());
//     try testing.expectEqualStrings("name", table.headers()[0]);
//     try testing.expectEqualStrings("alice", table.row(0)[0]);
//     try testing.expectEqualStrings("bob", table.row(1)[0]);
// }

const Args = @import("args.zig").Args;
const builtin = @import("builtin");
const completion = @import("completion.zig");
const csv = @import("csv.zig");
const Data = @import("data.zig").Data;
const detect = @import("detect.zig");
const json = @import("json.zig");
const sniffer = @import("sniffer.zig");
const std = @import("std");
const testing = std.testing;
const Table = @import("table.zig").Table;
const types = @import("types.zig");
const util = @import("util.zig");
const version = @import("build_options").version;
