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

    if (util.hasenv("BENCHMARK") and builtin.mode == .Debug) {
        try util.stderr.writeAll("tennis: BENCHMARK=1 requires `just benchmark` or a release build\n");
        std.process.exit(1);
    }

    var total = try std.time.Timer.start();
    defer util.benchmark("total", total.read());

    // allocators
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer {
        const check = gpa.deinit();
        if (builtin.mode == .Debug) std.debug.assert(check == .ok);
    }
    const alloc = gpa.allocator();

    //
    // arg processing
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
    // table
    //

    timer = try std.time.Timer.start();
    const input_bytes = try input.readToEndAlloc(alloc, std.math.maxInt(usize));
    defer alloc.free(input_bytes);

    const table = initTable(alloc, args.filename, args.config, input_bytes) catch |err| {
        const err_str = switch (err) {
            error.OutOfMemory => return err,
            error.InvalidJsonShape => "JSON input must be an array of objects",
            error.JaggedCsv => "All csv rows must have same number of columns",
            else => "That CSV file doesn't look right",
        };
        try printBanner(err_str);
        return 1;
    };
    defer table.deinit();
    util.benchmark("table.init", timer.read());

    timer = try std.time.Timer.start();
    try table.renderTable(util.stdout);
    util.benchmark("table.render", timer.read());
    return 0;
}

// Load input into a table using the detected format and delimiter.
fn initTable(alloc: std.mem.Allocator, filename: ?[]const u8, config_in: types.Config, bytes_in: []const u8) !*Table {
    // skip bom
    var bytes = bytes_in;
    if (std.mem.startsWith(u8, bytes, "\xef\xbb\xbf")) {
        bytes = bytes[3..];
    }

    var config = config_in;
    const format = try detect.detectFormat(alloc, filename, bytes);
    var data: Data = undefined;
    if (format == .csv) {
        if (config.delimiter == 0) config.delimiter = sniffer.sniff(bytes) orelse ',';
        data = try csv.load(alloc, bytes, config.delimiter);
    } else {
        data = try json.load(alloc, bytes);
    }
    return Table.init(alloc, config, data);
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

test "initTable strips UTF-8 BOM before CSV parsing" {
    const table = try initTable(testing.allocator, null, .{}, "\xef\xbb\xbfa,b\nc,d\n");
    defer table.deinit();

    try testing.expectEqualStrings("a", table.headers()[0]);
    try testing.expectEqualStrings("b", table.headers()[1]);
    try testing.expectEqualStrings("c", table.row(0)[0]);
    try testing.expectEqualStrings("d", table.row(0)[1]);
}

test "initTable strips UTF-8 BOM before JSONL parsing" {
    const table = try initTable(
        testing.allocator,
        "data.jsonl",
        .{},
        "\xef\xbb\xbf{\"name\":\"alice\"}\r\n{\"name\":\"bob\"}",
    );
    defer table.deinit();

    try testing.expectEqual(@as(usize, 2), table.nrows());
    try testing.expectEqualStrings("name", table.headers()[0]);
    try testing.expectEqualStrings("alice", table.row(0)[0]);
    try testing.expectEqualStrings("bob", table.row(1)[0]);
}

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
