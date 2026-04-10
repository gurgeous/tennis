//
// convenient stdout/stderr buffered writers
//

pub var stdout: *std.Io.Writer = undefined;
pub var stderr: *std.Io.Writer = undefined;

var stdout_buf: [4096]u8 = undefined;
var stderr_buf: [4096]u8 = undefined;

var stdout0: ?std.fs.File.Writer = null;
var stderr0: ?std.fs.File.Writer = null;
var env: ?std.process.EnvMap = null;

//
// init/deinit
//

// Initialize the shared buffered stdout/stderr writers.
pub fn init() void {
    stdout0 = .init(std.fs.File.stdout(), &stdout_buf);
    stderr0 = .init(std.fs.File.stderr(), &stderr_buf);
    stdout = &stdout0.?.interface;
    stderr = &stderr0.?.interface;
    env = std.process.getEnvMap(std.heap.page_allocator) catch @panic("could not load env");
}

// Release any shared runtime state initialized by init().
pub fn deinit() void {
    if (env) |*env0| env0.deinit();
    env = null;
}

//
// files
//

// does this file exist?
pub fn fileExists(path: []const u8) bool {
    const f = std.fs.cwd().openFile(path, .{}) catch return false;
    f.close();
    return true;
}

// Report whether the file handle supports seeking to the current position.
pub fn isSeekable(file: std.fs.File) bool {
    const pos = file.getPos() catch return false;
    file.seekTo(pos) catch return false;
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

// Return the min and max value in a non-empty slice.
pub fn minmax(comptime T: type, slice: []const T) ?struct { min: T, max: T } {
    if (slice.len == 0) return null;
    var min = slice[0];
    var max = slice[0];
    for (slice[1..]) |value| {
        if (value < min) min = value;
        if (value > max) max = value;
    }
    return .{ .min = min, .max = max };
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

// Quote one SQL identifier or string literal by doubling the quote character and wrapping it.
pub fn quoteSql(alloc: std.mem.Allocator, text: []const u8, quote: u8) ![]u8 {
    var escaped_quote: [2]u8 = .{ quote, quote };
    const escaped = try replaceAny(u8, alloc, text, &.{quote}, &escaped_quote);
    defer alloc.free(escaped);

    const out = try alloc.alloc(u8, escaped.len + 2);
    out[0] = quote;
    @memcpy(out[1 .. 1 + escaped.len], escaped);
    out[out.len - 1] = quote;
    return out;
}

// trim whitespace from slice
pub fn strip(comptime T: type, slice: []const T) []const T {
    return std.mem.trim(T, slice, &std.ascii.whitespace);
}

// Return the singular form or the singular form plus `s`.
pub fn plural(n: usize, comptime singular: []const u8) []const u8 {
    return if (n == 1) singular else singular ++ "s";
}

// Format one counted noun with thousands separators and pluralization.
pub fn pluralCount(alloc: std.mem.Allocator, n: usize, comptime singular: []const u8) ![]u8 {
    var buf: [32]u8 = undefined;
    const raw = try std.fmt.bufPrint(&buf, "{d}", .{n});
    const count = try int.intFormat(alloc, raw);
    defer alloc.free(count);
    return std.fmt.allocPrint(alloc, "{s} {s}", .{ count, plural(n, singular) });
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

//
// env
// Note: to use these only work if you call util.init, otherwise they always return null
//

// does this env var exist?
pub fn hasenv(name: []const u8) bool {
    return getenv(name) != null;
}

// Return one borrowed env var value when present.
pub fn getenv(name: []const u8) ?[]const u8 {
    return if (env) |env0| env0.get(name) else null;
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

// debug logging to stderr, enabled only with TENNIS_DEBUG=1 (or any value)
pub fn tdebug(comptime fmt: []const u8, args: anytype) void {
    if (!hasenv("TENNIS_DEBUG")) return;
    stderr.print("tennis: " ++ fmt ++ "\n", args) catch {};
    stderr.flush() catch {};
}

// how wide is the terminal? thanks mubi
pub fn termWidth() usize {
    const handle = switch (builtin.os.tag) {
        .windows => std.fs.File.stdout().handle,
        else => blk: {
            var tty = std.fs.openFileAbsolute("/dev/tty", .{}) catch return 80;
            defer tty.close();
            break :blk tty.handle;
        },
    };

    if (mibu.term.getSize(handle)) |size| {
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

test "minmax handles ints and empty slices" {
    const ints = [_]i64{ 4, -2, 9, 0 };
    const got = minmax(i64, &ints).?;
    try testing.expectEqual(@as(i64, -2), got.min);
    try testing.expectEqual(@as(i64, 9), got.max);
    try testing.expect(minmax(i64, &.{}) == null);
}

test "minmax handles floats" {
    const floats = [_]f64{ 1.5, 9.25, -3.0 };
    const got = minmax(f64, &floats).?;
    try testing.expectEqual(@as(f64, -3.0), got.min);
    try testing.expectEqual(@as(f64, 9.25), got.max);
}

test "isSeekable handles file and pipe" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const file = try tmp.dir.createFile("seekable.txt", .{ .read = true });
    defer file.close();
    try testing.expect(isSeekable(file));

    const pipe_fds = try std.posix.pipe();
    defer std.posix.close(pipe_fds[0]);
    defer std.posix.close(pipe_fds[1]);

    const pipe_file = std.fs.File{ .handle = pipe_fds[0] };
    try testing.expect(!isSeekable(pipe_file));
}

test "plural returns the right form" {
    try testing.expectEqualStrings("row", plural(1, "row"));
    try testing.expectEqualStrings("rows", plural(2, "row"));
}

test "pluralCount formats counts with separators and pluralization" {
    const one = try pluralCount(testing.allocator, 1, "row");
    defer testing.allocator.free(one);
    try testing.expectEqualStrings("1 row", one);

    const many = try pluralCount(testing.allocator, 1234, "row");
    defer testing.allocator.free(many);
    try testing.expectEqualStrings("1,234 rows", many);
}

test "fileExists" {
    const path = "testdata/test.csv";
    try testing.expect(fileExists(path));
    try testing.expect(!fileExists("testdata/definitely-missing.csv"));
}

test "hasenv" {
    init();
    defer deinit();
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
    const cases = [_]struct {
        haystack: []const u8,
        needle: []const u8,
        want: bool,
    }{
        .{ .haystack = "Hello", .needle = "ell", .want = true },
        .{ .haystack = "Hello", .needle = "EL", .want = true },
        .{ .haystack = "Hello", .needle = "world", .want = false },
        .{ .haystack = "Hello", .needle = "", .want = true },
    };

    for (cases) |tc| {
        try testing.expectEqual(tc.want, containsIgnoreCase(tc.haystack, tc.needle));
    }
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

test "quoteSql" {
    const cases = [_]struct {
        text: []const u8,
        quote: u8,
        want: []const u8,
    }{
        .{ .text = "plain", .quote = '"', .want = "\"plain\"" },
        .{ .text = "weird\"name", .quote = '"', .want = "\"weird\"\"name\"" },
        .{ .text = "plain", .quote = '\'', .want = "'plain'" },
        .{ .text = "weird'name", .quote = '\'', .want = "'weird''name'" },
    };

    for (cases) |tc| {
        const got = try quoteSql(testing.allocator, tc.text, tc.quote);
        defer testing.allocator.free(got);
        try testing.expectEqualStrings(tc.want, got);
    }
}

test "lowerAscii" {
    var buf: [16]u8 = undefined;
    try testing.expectEqualStrings(".json", lowerAscii(&buf, ".JSON"));
    try testing.expectEqualStrings("abc123", lowerAscii(&buf, "AbC123"));
    try testing.expectEqualStrings(".JSON", upperAscii(&buf, ".json"));
    try testing.expectEqualStrings("ABC123", upperAscii(&buf, "AbC123"));
}

test "sum" {
    try testing.expectEqual(@as(usize, 10), sum(usize, &.{ 1, 2, 3, 4 }));
}

test "termWidth returns a positive width" {
    try testing.expect(termWidth() > 0);
}

const builtin = @import("builtin");
const int = @import("int.zig");
const mibu = @import("mibu");
const std = @import("std");
const testing = std.testing;
