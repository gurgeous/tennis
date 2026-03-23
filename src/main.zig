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

    // BENCHMARK=1 sanity check
    if (util.hasenv("BENCHMARK") and builtin.mode == .Debug) {
        const fatal: failure.Failure = .{ .code = .benchmark_requires_release };
        try fatal.print();
        return 1;
    }

    // timer
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
    // args
    //

    var timer = try std.time.Timer.start();
    const argv = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, argv);
    const event = try Args.init(alloc, argv[1..]);
    defer event.deinit(alloc);
    util.benchmark("args", timer.read());

    //
    // handle early exits ("actions")
    //

    var config = switch (event) {
        .banner => {
            try failure.printBanner(util.stdout, null);
            return 0;
        },
        .completion => |shell| {
            try completion.write(alloc, shell);
            return 0;
        },
        .help => {
            try util.stdout.writeAll(Args.help);
            return 0;
        },
        .version => {
            try util.stdout.print("tennis: {s}\n", .{version});
            return 0;
        },
        .fatal => |fatal| {
            try fatal.print();
            return 1;
        },
        .run => |run| run,
    };

    //
    // where are we reading from?
    //

    timer = try std.time.Timer.start();
    var needs_close = false;
    var input = std.fs.File.stdin();
    const filename = config.filename;
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

    var data = load(alloc, config, input_bytes) catch |err| {
        if (err == error.OutOfMemory) return err;
        try (failure.Failure.fromError(err) orelse return err).print();
        return 1;
    };
    var data_moved = false;
    defer if (!data_moved) data.deinit(alloc);

    config.bind(alloc, data.headers()) catch |err| {
        const fatal = try failure.Failure.fromTableError(alloc, err, data.headers());
        defer fatal.deinit(alloc);
        try fatal.print();
        return 1;
    };
    defer config.deinit(alloc);

    //
    // data => table
    //

    const table = try Table.init(alloc, config, data);
    data_moved = true;
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

fn load(alloc: std.mem.Allocator, config: types.Config, bytes_in: []const u8) !Data {
    // skip bom
    var bytes = bytes_in;
    if (std.mem.startsWith(u8, bytes, "\xef\xbb\xbf")) {
        bytes = bytes[3..];
    }

    const format = try detect.detectFormat(alloc, config.filename, bytes);
    if (format == .json) {
        return try json.load(alloc, bytes);
    }

    var delimiter = config.delimiter;
    if (delimiter == 0) delimiter = sniffer.sniff(bytes) orelse ',';
    return try csv.load(alloc, bytes, delimiter);
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
        const data = try load(testing.allocator, tc.config, tc.input);
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
const sniffer = @import("sniffer.zig");
const std = @import("std");
const testing = std.testing;
const Table = @import("table.zig").Table;
const types = @import("types.zig");
const util = @import("util.zig");
const version = @import("build_options").version;
