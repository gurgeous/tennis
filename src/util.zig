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

// Return an owned slice containing only the items kept by `keep`.
pub fn filter(comptime T: type, alloc: std.mem.Allocator, input: []const T, comptime keep: fn (T) bool) ![]T {
    var out: std.ArrayList(T) = .empty;
    defer out.deinit(alloc);

    for (input) |item| {
        if (keep(item)) try out.append(alloc, item);
    }
    return out.toOwnedSlice(alloc);
}

// Return an owned slice filled with ascending indexes from 0 to len - 1.
pub fn range(alloc: std.mem.Allocator, len: usize) ![]usize {
    const out = try alloc.alloc(usize, len);
    for (out, 0..) |*slot, ii| slot.* = ii;
    return out;
}

//
// string
//

// quote a string, keeping printable ascii readable and hex-escaping the rest
pub fn inspect(alloc: std.mem.Allocator, s: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(alloc);

    try out.append(alloc, '"');
    for (s) |c| {
        switch (c) {
            '"', '\\' => {
                try out.append(alloc, '\\');
                try out.append(alloc, c);
            },
            '\t' => try out.appendSlice(alloc, "\\t"),
            '\n' => try out.appendSlice(alloc, "\\n"),
            '\r' => try out.appendSlice(alloc, "\\r"),
            '\x1b' => try out.appendSlice(alloc, "\\e"),
            else => {
                if (c >= 0x20 and c <= 0x7e) {
                    try out.append(alloc, c);
                } else {
                    try out.writer(alloc).print("\\x{x:0>2}", .{c});
                }
            },
        }
    }
    try out.append(alloc, '"');
    return out.toOwnedSlice(alloc);
}

// Lowercase ASCII bytes from `src` into `dest` and return the written prefix.
pub fn lowerAscii(dest: []u8, src: []const u8) []const u8 {
    std.debug.assert(dest.len >= src.len);
    for (src, 0..) |ch, ii| {
        dest[ii] = std.ascii.toLower(ch);
    }
    return dest[0..src.len];
}

// Report whether `needle` appears in `haystack` with ASCII case folded.
pub fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (needle.len > haystack.len) return false;

    var ii: usize = 0;
    while (ii + needle.len <= haystack.len) : (ii += 1) {
        for (needle, 0..) |want, jj| {
            if (std.ascii.toLower(haystack[ii + jj]) != std.ascii.toLower(want)) break;
        } else return true;
    }
    return false;
}

// Replace any item found in `find` with `replace`. O(N^2) but doesn't matter for our purposes.
pub fn replaceAny(comptime T: type, alloc: std.mem.Allocator, input: []const T, find: []const T, replace: []const T) ![]T {
    var out: std.ArrayList(T) = .empty;
    defer out.deinit(alloc);

    for (input) |ch| {
        for (find) |n| {
            if (ch == n) {
                try out.appendSlice(alloc, replace);
                break;
            }
        } else {
            try out.append(alloc, ch);
        }
    }
    return out.toOwnedSlice(alloc);
}

// trim whitespace from slice
pub fn strip(comptime T: type, slice: []const T) []const T {
    return std.mem.trim(T, slice, &std.ascii.whitespace);
}

// Borrow the bytes associated with a scalar JSON token.
pub fn tokenBytes(token: std.json.Token) []const u8 {
    return switch (token) {
        .allocated_number, .allocated_string, .number, .string => |v| v,
        else => unreachable,
    };
}

// Uppercase ASCII bytes from `src` into `dest` and return the written prefix.
pub fn upperAscii(dest: []u8, src: []const u8) []const u8 {
    std.debug.assert(dest.len >= src.len);
    for (src, 0..) |ch, ii| {
        dest[ii] = std.ascii.toUpper(ch);
    }
    return dest[0..src.len];
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
    stderr.print("{s:<17} {d:>8}.{d:0>3} ms\n", .{ label, ms, frac }) catch {};
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
// testing
//

test "digits" {
    try testing.expectEqual(@as(usize, 1), digits(usize, 0));
    try testing.expectEqual(@as(usize, 1), digits(usize, 7));
    try testing.expectEqual(@as(usize, 3), digits(usize, 123));
}

test "filter keeps matching items" {
    const items = [_]usize{ 1, 2, 3, 4, 5 };
    const got = try filter(usize, testing.allocator, &items, struct {
        fn keep(n: usize) bool {
            return n % 2 == 0;
        }
    }.keep);
    defer testing.allocator.free(got);

    try testing.expectEqualSlices(usize, &.{ 2, 4 }, got);
}

test "filter handles empty result" {
    const items = [_][]const u8{ "a", "bb", "ccc" };
    const got = try filter([]const u8, testing.allocator, &items, struct {
        fn keep(s: []const u8) bool {
            return s.len > 10;
        }
    }.keep);
    defer testing.allocator.free(got);

    try testing.expectEqual(@as(usize, 0), got.len);
}

test "fileExists" {
    const path = "testdata/test.csv";
    try testing.expect(fileExists(path));
    try testing.expect(!fileExists("testdata/definitely-missing.csv"));
}

test "hasenv" {
    try testing.expect(hasenv("PATH"));
    try testing.expect(!hasenv("TENNIS_TEST_ENV_DOES_NOT_EXIST"));
}

test "inspect" {
    const s1 = try inspect(testing.allocator, "abc 123");
    defer testing.allocator.free(s1);
    try testing.expectEqualStrings("\"abc 123\"", s1);

    const s2 = try inspect(testing.allocator, &[_]u8{
        '"', '\\', '\t', '\x1b', '\r', '\n', '\x08', '\x0c', '\x0b', 0xff,
    });
    defer testing.allocator.free(s2);
    try testing.expectEqualStrings("\"\\\"\\\\\\t\\e\\r\\n\\x08\\x0c\\x0b\\xff\"", s2);
}

test "containsIgnoreCase" {
    try testing.expect(containsIgnoreCase("Hello", "ell"));
    try testing.expect(containsIgnoreCase("Hello", "EL"));
    try testing.expect(!containsIgnoreCase("Hello", "world"));
    try testing.expect(containsIgnoreCase("Hello", ""));
}

test "readByte" {
    const fds = try std.posix.pipe();
    defer std.posix.close(fds[0]);
    defer std.posix.close(fds[1]);

    _ = try std.posix.write(fds[1], "z");
    try testing.expectEqual(@as(u8, 'z'), try readByte(fds[0]));
}

test "strip" {
    try testing.expectEqualStrings("abc", strip(u8, " \t abc\r\n"));
}

test "replaceAny" {
    const alloc = testing.allocator;

    const s1 = try replaceAny(u8, alloc, "abc", "x", "_");
    defer alloc.free(s1);
    try testing.expectEqualStrings("abc", s1);

    const s2 = try replaceAny(u8, alloc, "abc", "b", "_");
    defer alloc.free(s2);
    try testing.expectEqualStrings("a_c", s2);

    const s3 = try replaceAny(u8, alloc, "abcde", "bcd", "_");
    defer alloc.free(s3);
    try testing.expectEqualStrings("a___e", s3);

    const s4 = try replaceAny(u8, alloc, "a\rb\nc\t", "\r\n\t", " ");
    defer alloc.free(s4);
    try testing.expectEqualStrings("a b c ", s4);

    const s5 = try replaceAny(u8, alloc, "abc", "b", "--");
    defer alloc.free(s5);
    try testing.expectEqualStrings("a--c", s5);

    const s6 = try replaceAny(u8, alloc, "abc", "b", "");
    defer alloc.free(s6);
    try testing.expectEqualStrings("ac", s6);
}

test "lowerAscii" {
    var buf: [16]u8 = undefined;
    try testing.expectEqualStrings(".json", lowerAscii(&buf, ".JSON"));
    try testing.expectEqualStrings("abc123", lowerAscii(&buf, "AbC123"));
    try testing.expectEqualStrings(".JSON", upperAscii(&buf, ".json"));
    try testing.expectEqualStrings("ABC123", upperAscii(&buf, "AbC123"));
}

test "truncate" {
    var buf: [256]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);

    try truncate(&writer, "this is too long", 8);
    try testing.expectEqualStrings("this is…", writer.buffered());
    writer.end = 0;

    try truncate(&writer, "éééé", 3);
    try testing.expectEqualStrings("éé…", writer.buffered());
    writer.end = 0;

    try truncate(&writer, "abcdef", 0);
    try testing.expectEqualStrings("", writer.buffered());
}

test "sum" {
    try testing.expectEqual(@as(usize, 10), sum(usize, &.{ 1, 2, 3, 4 }));
}

test "tdebug" {
    tdebug("off {d}", .{1});
    tdebug("on {d}", .{2});
}

test "termWidth returns a positive width" {
    try testing.expect(termWidth() > 0);
}

const mibu = @import("mibu");
const std = @import("std");
const testing = std.testing;
