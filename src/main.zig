const version = @import("build_options").version;

pub fn main() !void {
    const code = try main0();
    std.process.exit(code);
}

fn main0() !u8 {
    // always flush
    defer util.stdout.flush() catch {};

    // allocators
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    //
    // arg processing
    //

    const argv = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, argv);
    const args = try Args.init(alloc, argv[1..]);
    defer if (args.err_str) |msg| alloc.free(msg);

    //
    // handle early exits ("actions")
    //

    if (args.action) |action| {
        switch (action) {
            .banner => try printBanner(null),
            .help => try Args.writeHelp(util.stdout),
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

    //
    // read all records into memory
    //

    const records = util.readCsv(alloc, input) catch |err| {
        if (err == error.OutOfMemory) return err;
        const err_str = if (err == error.JaggedCsv)
            "All csv rows must have same number of columns"
        else
            "That CSV file doesn't look right";
        try printBanner(err_str);
        return 1;
    };
    defer util.freeCsv(alloc, records);

    //
    // table
    //

    var table: Table = .init(alloc, args.config);
    try table.render(records, util.stdout);
    return 0;
}

fn printBanner(err_str: ?[]const u8) !void {
    if (err_str) |s| {
        try util.stdout.print("tennis: {s}\n", .{s});
    }
    try util.stdout.writeAll("tennis: try 'tennis --help' for more information\n");
}

test {
    _ = @import("args.zig");
    _ = @import("color.zig");
    _ = @import("layout.zig");
    _ = @import("render.zig");
    _ = @import("style.zig");
    _ = @import("termbg.zig");
    _ = @import("util.zig");
}

const Args = @import("args.zig").Args;
const std = @import("std");
const Table = @import("table.zig").Table;
const util = @import("util.zig");
