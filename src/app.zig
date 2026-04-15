// Process runtime context shared across the CLI.

// Owns allocator, IO, environment, and shared buffered stdio for one run.
pub const App = struct {
    alloc: std.mem.Allocator,
    io: std.Io,
    environ: std.process.Environ,
    env: std.process.Environ.Map,
    stdout_buf: [4096]u8 = undefined,
    stderr_buf: [4096]u8 = undefined,
    stdout_writer: std.Io.File.Writer = undefined,
    stderr_writer: std.Io.File.Writer = undefined,

    const Self = @This();

    //
    // ctor
    //

    // Build the runtime app context from juicy main.
    pub fn init(ip: std.process.Init) !*Self {
        return try initFrom(ip.gpa, ip.io, ip.minimal.environ);
    }

    // Build a test app context from std.testing globals.
    pub fn testInit(alloc: std.mem.Allocator) !*Self {
        return try initFrom(alloc, std.testing.io, std.testing.environ);
    }

    // Initialize one App from explicit runtime pieces.
    fn initFrom(alloc: std.mem.Allocator, io: std.Io, environ: std.process.Environ) !*Self {
        const app = try alloc.create(Self);
        app.* = .{
            .alloc = alloc,
            .io = io,
            .environ = environ,
            .env = try std.process.Environ.createMap(environ, alloc),
        };
        app.stdout_writer = std.Io.File.stdout().writerStreaming(io, &app.stdout_buf);
        app.stderr_writer = std.Io.File.stderr().writerStreaming(io, &app.stderr_buf);
        return app;
    }

    // Release owned runtime state.
    pub fn destroy(self: *Self) void {
        self.env.deinit();
        self.alloc.destroy(self);
    }

    // Return the shared buffered stdout writer.
    pub fn stdout(self: *Self) *std.Io.Writer {
        return &self.stdout_writer.interface;
    }

    // Return the shared buffered stderr writer.
    pub fn stderr(self: *Self) *std.Io.Writer {
        return &self.stderr_writer.interface;
    }

    // Flush shared buffered stdout and stderr.
    pub fn flush(self: *Self) void {
        self.stdout().flush() catch {};
        self.stderr().flush() catch {};
    }

    // Report whether one env var exists.
    pub fn hasenv(self: *const Self, name: []const u8) bool {
        return self.getenv(name) != null;
    }

    // Return one borrowed env var value when present.
    pub fn getenv(self: *const Self, name: []const u8) ?[]const u8 {
        return self.env.get(name);
    }

    // Print one benchmark line when BENCHMARK is enabled.
    pub fn benchmark(self: *const Self, label: []const u8, elapsed_ns: u64) void {
        if (!self.hasenv("BENCHMARK")) return;
        const ms = elapsed_ns / std.time.ns_per_ms;
        const frac = (elapsed_ns % std.time.ns_per_ms) / std.time.ns_per_us;
        var buf: [256]u8 = undefined;
        var writer = std.Io.File.stderr().writerStreaming(self.io, &buf);
        writer.interface.print("{s:<17} {d:>8}.{d:0>3} ms\n", .{ label, ms, frac }) catch {};
        writer.interface.flush() catch {};
    }

    // Print one debug line when TENNIS_DEBUG is enabled.
    pub fn tdebug(self: *const Self, comptime fmt: []const u8, args: anytype) void {
        if (!self.hasenv("TENNIS_DEBUG")) return;
        var buf: [256]u8 = undefined;
        var writer = std.Io.File.stderr().writerStreaming(self.io, &buf);
        writer.interface.print("tennis: " ++ fmt ++ "\n", args) catch {};
        writer.interface.flush() catch {};
    }

    // Return the detected terminal width with the usual fallback.
    pub fn termWidth(self: *const Self) usize {
        if (builtin.os.tag != .windows) {
            if (termWidthHandle(std.Io.File.stdout().handle)) |width| return width;
            const tty = std.Io.Dir.openFileAbsolute(self.io, "/dev/tty", .{}) catch return 80;
            defer tty.close(self.io);
            if (termWidthHandle(tty.handle)) |width| return width;
        } else {
            if (termWidthHandle(std.Io.File.stdout().handle)) |width| return width;
        }

        return 80;
    }
};

// Probe one handle and return its positive terminal width when available.
fn termWidthHandle(handle: std.Io.File.Handle) ?usize {
    if (mibu.term.getSize(handle)) |size| {
        if (size.width > 0) return @intCast(size.width);
    } else |_| {}
    return null;
}

//
// testing
//

test "testInit exposes env" {
    const app = try App.testInit(testing.allocator);
    defer app.destroy();

    try testing.expect(app.hasenv("PATH"));
    _ = std.Io.File.stdin().isTty(app.io) catch false;
    _ = std.Io.File.stdout().isTty(app.io) catch false;
}

test "termWidth returns a positive width" {
    const app = try App.testInit(testing.allocator);
    defer app.destroy();

    try testing.expect(app.termWidth() > 0);
}

const builtin = @import("builtin");
const mibu = @import("mibu");
const std = @import("std");
const testing = std.testing;
