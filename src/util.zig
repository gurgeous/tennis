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
// misc helpers
//

// does this env var exist?
pub fn hasenv(name: []const u8) bool {
    return std.posix.getenv(name) != null;
}

// does this file exist?
pub fn fileExists(path: []const u8) bool {
    const f = std.fs.cwd().openFile(path, .{}) catch return false;
    f.close();
    return true;
}

// how many digits in n?
pub fn digits(comptime T: type, n: T) usize {
    if (@typeInfo(T) != .int) @compileError("digits expects an integer type");
    if (n == 0) return 1;
    var v = n;
    var d: usize = 0;
    while (v > 0) : (v /= 10) d += 1;
    return d;
}

// trim whitespace from slice
pub fn strip(comptime T: type, slice: []const T) []const T {
    const whitespace = [_]T{ ' ', '\t', '\r', '\n' };
    return std.mem.trim(T, slice, &whitespace);
}

// sum values in slice
pub fn sum(comptime T: type, slice: []const T) T {
    var total: T = 0;
    for (slice) |w| total += w;
    return total;
}

// Return the terminal display width of a UTF-8 string.
pub fn displayWidth(s: []const u8) usize {
    return std.unicode.utf8CountCodepoints(s) catch s.len;
}

// how wide is ther terminal? thanks mubi
pub fn termWidth() usize {
    var tty = std.fs.openFileAbsolute("/dev/tty", .{}) catch return 80;
    defer tty.close();

    if (mibu.term.getSize(tty.handle)) |size| {
        if (size.width > 0) return @intCast(size.width);
    } else |_| {}
    return 80;
}

// read a single byte from an fd
pub fn readByte(fd: std.posix.fd_t) !u8 {
    var buf: [1]u8 = undefined;
    const n = try std.posix.read(fd, &buf);
    if (n != 1) return error.EndOfStream;
    return buf[0];
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

// debug logging to stderr, enabled only with TENNIS_DEBUG=1 (or any value)
pub fn tdebug(comptime fmt: []const u8, args: anytype) void {
    if (!hasenv("TENNIS_DEBUG")) return;
    stderr.print("tennis: " ++ fmt ++ "\n", args) catch {};
    stderr.flush() catch {};
}

//
// tests
//

test "hasenv detects environment variables" {
    try std.testing.expect(hasenv("PATH"));
    try std.testing.expect(!hasenv("TENNIS_TEST_ENV_DOES_NOT_EXIST"));
}

test "fileExists handles present and missing files" {
    const path = "testdata/test.csv";
    try std.testing.expect(fileExists(path));
    try std.testing.expect(!fileExists("testdata/definitely-missing.csv"));
}

test "digits counts decimal width" {
    try std.testing.expectEqual(@as(usize, 1), digits(usize, 0));
    try std.testing.expectEqual(@as(usize, 1), digits(usize, 7));
    try std.testing.expectEqual(@as(usize, 3), digits(usize, 123));
}

test "strip trims ascii whitespace" {
    try std.testing.expectEqualStrings("abc", strip(u8, " \t abc\r\n"));
}

test "sum adds a slice" {
    try std.testing.expectEqual(@as(usize, 10), sum(usize, &.{ 1, 2, 3, 4 }));
}

test "displayWidth handles ascii and utf8" {
    try std.testing.expectEqual(@as(usize, 3), displayWidth("abc"));
    try std.testing.expectEqual(@as(usize, 2), displayWidth("éé"));
    try std.testing.expectEqual(@as(usize, 1), displayWidth("—"));
}

test "displayWidth falls back on invalid utf8" {
    try std.testing.expectEqual(@as(usize, 2), displayWidth(&[_]u8{ 0xff, 0x61 }));
}

test "termWidth returns a positive width" {
    try std.testing.expect(termWidth() > 0);
}

test "readByte reads a single byte" {
    const fds = try std.posix.pipe();
    defer std.posix.close(fds[0]);
    defer std.posix.close(fds[1]);

    _ = try std.posix.write(fds[1], "z");
    try std.testing.expectEqual(@as(u8, 'z'), try readByte(fds[0]));
}

test "inspect keeps printable ascii readable" {
    const s = try inspect(std.testing.allocator, "abc 123");
    defer std.testing.allocator.free(s);
    try std.testing.expectEqualStrings("\"abc 123\"", s);
}

test "inspect escapes quotes slash and bytes" {
    const s = try inspect(std.testing.allocator, &[_]u8{ '"', '\\', '\n', 0xff });
    defer std.testing.allocator.free(s);
    try std.testing.expectEqualStrings("\"\\\"\\\\\\x0a\\xff\"", s);
}

test "tdebug is callable" {
    tdebug("off {d}", .{1});
    tdebug("on {d}", .{2});
}

const std = @import("std");
const mibu = @import("mibu");
