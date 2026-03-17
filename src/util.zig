//
// convenient stdout/stderr buffered writers
//

var stdout_buf: [4096]u8 = undefined;
var stderr_buf: [4096]u8 = undefined;

var stdout0: std.fs.File.Writer = .init(std.fs.File.stdout(), &stdout_buf);
var stderr0: std.fs.File.Writer = .init(std.fs.File.stderr(), &stderr_buf);

pub const stdout = &stdout0.interface;
pub const stderr = &stderr0.interface;

//
// files
//

// does this file exist?
pub fn fileExists(path: []const u8) bool {
    const f = std.fs.cwd().openFile(path, .{}) catch return false;
    f.close();
    return true;
}

// read a single byte from an fd
pub fn readByte(fd: std.posix.fd_t) !u8 {
    var buf: [1]u8 = undefined;
    const n = try std.posix.read(fd, &buf);
    if (n != 1) return error.EndOfStream;
    return buf[0];
}

//
// numeric
//

// how many digits in n?
pub fn digits(comptime T: type, n: T) usize {
    if (@typeInfo(T) != .int) @compileError("digits expects an integer type");
    if (n == 0) return 1;
    var v = n;
    var d: usize = 0;
    while (v > 0) : (v /= 10) d += 1;
    return d;
}

//
// slices
//

// sum values in slice
pub fn sum(comptime T: type, slice: []const T) T {
    var total: T = 0;
    for (slice) |w| total += w;
    return total;
}

//
// string
//

// Return the terminal display width of a UTF-8 string.
pub fn displayWidth(s: []const u8) usize {
    return std.unicode.utf8CountCodepoints(s) catch s.len;
}

// quote a string, keeping printable ascii readable and hex-escaping the rest
pub fn inspect(alloc: std.mem.Allocator, s: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(alloc);

    try out.append(alloc, '"');
    for (s) |c| {
        if (c == '"' or c == '\\') {
            try out.append(alloc, '\\');
            try out.append(alloc, c);
        } else if (c >= 0x20 and c <= 0x7e) {
            try out.append(alloc, c);
        } else {
            try out.writer(alloc).print("\\x{x:0>2}", .{c});
        }
    }
    try out.append(alloc, '"');
    return out.toOwnedSlice(alloc);
}

// trim whitespace from slice
pub fn strip(comptime T: type, slice: []const T) []const T {
    const whitespace = [_]T{ ' ', '\t', '\r', '\n' };
    return std.mem.trim(T, slice, &whitespace);
}

// write text truncated to width, using an ellipsis when needed
pub fn truncate(writer: *std.Io.Writer, text: []const u8, stop: usize) !void {
    if (stop == 0) return;

    var it = std.unicode.Utf8View.init(text) catch {
        try writer.writeAll(text[0..@min(text.len, stop)]);
        return;
    };
    var iter = it.iterator();

    var used: usize = 0;
    while (iter.nextCodepointSlice()) |cp_slice| {
        if (used + 1 >= stop) break;
        try writer.writeAll(cp_slice);
        used += 1;
    }
    try writer.writeAll("…");
}

//
// misc
//

// print a benchmark line
pub fn benchmark(label: []const u8, elapsed_ns: u64) void {
    if (!hasenv("BENCHMARK")) return;
    const ms = elapsed_ns / std.time.ns_per_ms;
    const frac = (elapsed_ns % std.time.ns_per_ms) / std.time.ns_per_us;
    stderr.print("{s:<16} {d:>8}.{d:0>3} ms\n", .{ label, ms, frac }) catch {};
    stderr.flush() catch {};
}

// does this env var exist?
pub fn hasenv(name: []const u8) bool {
    return std.posix.getenv(name) != null;
}

// debug logging to stderr, enabled only with TENNIS_DEBUG=1 (or any value)
pub fn tdebug(comptime fmt: []const u8, args: anytype) void {
    if (!hasenv("TENNIS_DEBUG")) return;
    stderr.print("tennis: " ++ fmt ++ "\n", args) catch {};
    stderr.flush() catch {};
}

// how wide is the terminal? thanks mubi
pub fn termWidth() usize {
    var tty = std.fs.openFileAbsolute("/dev/tty", .{}) catch return 80;
    defer tty.close();

    if (mibu.term.getSize(tty.handle)) |size| {
        if (size.width > 0) return @intCast(size.width);
    } else |_| {}
    return 80;
}

//
// tests
//

test "digits" {
    try std.testing.expectEqual(@as(usize, 1), digits(usize, 0));
    try std.testing.expectEqual(@as(usize, 1), digits(usize, 7));
    try std.testing.expectEqual(@as(usize, 3), digits(usize, 123));
}

test "displayWidth" {
    try std.testing.expectEqual(@as(usize, 3), displayWidth("abc"));
    try std.testing.expectEqual(@as(usize, 2), displayWidth("éé"));
    try std.testing.expectEqual(@as(usize, 1), displayWidth("—"));
    try std.testing.expectEqual(@as(usize, 2), displayWidth(&[_]u8{ 0xff, 0x61 }));
}

test "fileExists" {
    const path = "testdata/test.csv";
    try std.testing.expect(fileExists(path));
    try std.testing.expect(!fileExists("testdata/definitely-missing.csv"));
}

test "hasenv" {
    try std.testing.expect(hasenv("PATH"));
    try std.testing.expect(!hasenv("TENNIS_TEST_ENV_DOES_NOT_EXIST"));
}

test "inspect" {
    const s1 = try inspect(std.testing.allocator, "abc 123");
    defer std.testing.allocator.free(s1);
    try std.testing.expectEqualStrings("\"abc 123\"", s1);

    const s2 = try inspect(std.testing.allocator, &[_]u8{ '"', '\\', '\n', 0xff });
    defer std.testing.allocator.free(s2);
    try std.testing.expectEqualStrings("\"\\\"\\\\\\x0a\\xff\"", s2);
}

test "readByte" {
    const fds = try std.posix.pipe();
    defer std.posix.close(fds[0]);
    defer std.posix.close(fds[1]);

    _ = try std.posix.write(fds[1], "z");
    try std.testing.expectEqual(@as(u8, 'z'), try readByte(fds[0]));
}

test "strip" {
    try std.testing.expectEqualStrings("abc", strip(u8, " \t abc\r\n"));
}

test "truncate" {
    var buf: [256]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);

    try truncate(&writer, "this is too long", 8);
    try std.testing.expectEqualStrings("this is…", writer.buffered());
    writer.end = 0;

    try truncate(&writer, "éééé", 3);
    try std.testing.expectEqualStrings("éé…", writer.buffered());
    writer.end = 0;

    try truncate(&writer, "abcdef", 0);
    try std.testing.expectEqualStrings("", writer.buffered());
}

test "sum" {
    try std.testing.expectEqual(@as(usize, 10), sum(usize, &.{ 1, 2, 3, 4 }));
}

test "tdebug" {
    tdebug("off {d}", .{1});
    tdebug("on {d}", .{2});
}

test "termWidth returns a positive width" {
    try std.testing.expect(termWidth() > 0);
}

const mibu = @import("mibu");
const std = @import("std");
