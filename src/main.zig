pub fn main() !void {
    const code = try main0();
    std.process.exit(code);
}

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

    // try to sniff delim if necessary
    var replay = try ReplayReader(std.fs.File).init(alloc, input, 4096);
    defer replay.deinit();

    var config = args.config;
    if (config.delimiter == 0) config.delimiter = try sniff(alloc, replay.buffer());

    const table = Table.init(alloc, config, replay.reader()) catch |err| {
        if (err == error.OutOfMemory) return err;
        const err_str = if (err == error.JaggedCsv)
            "All csv rows must have same number of columns"
        else
            "That CSV file doesn't look right";
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

fn sniff(alloc: std.mem.Allocator, sample: []const u8) !u8 {
    if (sniffer.sniff(sample)) |delimiter| {
        const label = try util.inspect(alloc, &[_]u8{delimiter});
        defer alloc.free(label);
        util.tdebug("sniffed delimiter {s}", .{label});
        return delimiter;
    }

    util.tdebug("could not sniff delimiter, falling back to comma", .{});
    return ',';
}

fn printBanner(err_str: ?[]const u8) !void {
    try printBannerTo(util.stdout, util.stderr, err_str);
}

fn printBannerTo(stdout_writer: *std.Io.Writer, stderr_writer: *std.Io.Writer, err_str: ?[]const u8) !void {
    const writer = if (err_str != null) stderr_writer else stdout_writer;
    if (err_str) |s| {
        try writer.print("tennis: {s}\n", .{s});
    }
    try writer.writeAll("tennis: try 'tennis --help' for more information\n");
}

test {
    _ = @import("args.zig");
    _ = @import("border.zig");
    _ = @import("column.zig");
    _ = @import("completion.zig");
    _ = @import("color.zig");
    _ = @import("csv.zig");
    _ = @import("doomicode.zig");
    _ = @import("float.zig");
    _ = @import("layout.zig");
    _ = @import("replay.zig");
    _ = @import("render.zig");
    _ = @import("sniffer.zig");
    _ = @import("style.zig");
    _ = @import("termbg.zig");
    _ = @import("util.zig");
}

test "printBanner writes normal banner to stdout" {
    var stdout_buf: [256]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_writer = std.Io.Writer.fixed(&stdout_buf);
    var stderr_writer = std.Io.Writer.fixed(&stderr_buf);

    try printBannerTo(&stdout_writer, &stderr_writer, null);

    try std.testing.expectEqualStrings(
        "tennis: try 'tennis --help' for more information\n",
        stdout_writer.buffered(),
    );
    try std.testing.expectEqualStrings("", stderr_writer.buffered());
}

test "printBanner writes errors to stderr" {
    var stdout_buf: [256]u8 = undefined;
    var stderr_buf: [256]u8 = undefined;
    var stdout_writer = std.Io.Writer.fixed(&stdout_buf);
    var stderr_writer = std.Io.Writer.fixed(&stderr_buf);

    try printBannerTo(&stdout_writer, &stderr_writer, "bad csv");

    try std.testing.expectEqualStrings("", stdout_writer.buffered());
    try std.testing.expectEqualStrings(
        "tennis: bad csv\ntennis: try 'tennis --help' for more information\n",
        stderr_writer.buffered(),
    );
}

const Args = @import("args.zig").Args;
const builtin = @import("builtin");
const completion = @import("completion.zig");
const ReplayReader = @import("replay.zig").ReplayReader;
const sniffer = @import("sniffer.zig");
const std = @import("std");
const Table = @import("table.zig").Table;
const types = @import("types.zig");
const util = @import("util.zig");
const version = @import("build_options").version;
