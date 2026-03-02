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

pub fn hasenv(name: []const u8) bool {
    return std.posix.getenv(name) != null;
}

pub fn fileExists(path: []const u8) bool {
    const f = std.fs.cwd().openFile(path, .{}) catch return false;
    f.close();
    return true;
}

pub fn digits(comptime T: type, n: T) usize {
    if (@typeInfo(T) != .int) @compileError("digits expects an integer type");
    if (n == 0) return 1;
    var v = n;
    var d: usize = 0;
    while (v > 0) : (v /= 10) d += 1;
    return d;
}

pub fn strip(comptime T: type, slice: []const T) []const T {
    const whitespace = [_]T{ ' ', '\t', '\r', '\n' };
    return std.mem.trim(T, slice, &whitespace);
}

pub fn sum(comptime T: type, slice: []const T) T {
    var total: T = 0;
    for (slice) |w| total += w;
    return total;
}

pub fn termwidth() usize {
    var tty = std.fs.openFileAbsolute("/dev/tty", .{}) catch return 80;
    defer tty.close();

    if (mibu.term.getSize(tty.handle)) |size| {
        if (size.width > 0) return @intCast(size.width);
    } else |_| {}
    return 80;
}

// Read a csv into memory. reader is anything that supports readAll
// (std.fs.File). Trim whitespace as we go.
pub fn readCsv(alloc: std.mem.Allocator, reader: anytype) ![][][]const u8 {
    var rows = std.ArrayList([][]const u8).empty;
    errdefer {
        const owned = rows.items;
        for (owned) |row| {
            for (row) |field| alloc.free(field);
            alloc.free(row);
        }
        rows.deinit(alloc);
    }
    var parser = zig_csv.allocs.column.init(alloc, reader, .{});
    var width: ?usize = null;
    while (parser.next()) |csv| {
        defer csv.deinit();

        // bail if jagged
        if (width) |expected| {
            if (csv.len() != expected) return error.JaggedCsv;
        } else {
            width = csv.len();
        }

        const row = try alloc.alloc([]const u8, csv.len());
        var ii: usize = 0;
        errdefer {
            for (row[0..ii]) |field| alloc.free(field);
            alloc.free(row);
        }
        var iter = csv.iter();
        while (iter.next()) |field| : (ii += 1) {
            row[ii] = try alloc.dupe(u8, strip(u8, field.data()));
        }
        try rows.append(alloc, row);
    }
    if (parser.err) |e| return e;
    return rows.toOwnedSlice(alloc);
}

pub fn freeCsv(alloc: std.mem.Allocator, rows: [][][]const u8) void {
    for (rows) |row| {
        for (row) |field| alloc.free(field);
        alloc.free(row);
    }
    alloc.free(rows);
}

// read a single byte from an fd
pub fn readByte(fd: std.posix.fd_t) !u8 {
    var buf: [1]u8 = undefined;
    const n = try std.posix.read(fd, &buf);
    if (n != 1) return error.EndOfStream;
    return buf[0];
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

test "termwidth returns a positive width" {
    try std.testing.expect(termwidth() > 0);
}

test "readCsv handles quoted comma and escaped quote" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var in = std.io.fixedBufferStream("a,b\n\"x,y\",\"say \"\"hi\"\"\"\n");
    const rows = try readCsv(alloc, in.reader());
    try std.testing.expectEqual(2, rows.len);
    try std.testing.expectEqualStrings("a", rows[0][0]);
    try std.testing.expectEqualStrings("b", rows[0][1]);
    try std.testing.expectEqualStrings("x,y", rows[1][0]);
    try std.testing.expectEqualStrings("say \"hi\"", rows[1][1]);
}

test "readCsv rejects jagged rows" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var in = std.io.fixedBufferStream("a,b\nc\n");
    try std.testing.expectError(error.JaggedCsv, readCsv(alloc, in.reader()));
}

test "readCsv rejects malformed csv" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var in = std.io.fixedBufferStream("a,b\n\"oops\n");
    try std.testing.expectError(error.UnexpectedEndOfFile, readCsv(alloc, in.reader()));
}

test "readCsv trims whitespace" {
    const alloc = std.testing.allocator;
    var in = std.io.fixedBufferStream(" a , b \n c , d \n");
    const rows = try readCsv(alloc, in.reader());
    defer freeCsv(alloc, rows);

    try std.testing.expectEqualStrings("a", rows[0][0]);
    try std.testing.expectEqualStrings("b", rows[0][1]);
    try std.testing.expectEqualStrings("c", rows[1][0]);
    try std.testing.expectEqualStrings("d", rows[1][1]);
}

test "readCsv empty input yields empty header cell" {
    const alloc = std.testing.allocator;
    var in = std.io.fixedBufferStream("");
    const rows = try readCsv(alloc, in.reader());
    defer freeCsv(alloc, rows);

    try std.testing.expectEqual(1, rows.len);
    try std.testing.expectEqual(1, rows[0].len);
    try std.testing.expectEqual(0, rows[0][0].len);
}

test "freeCsv releases owned rows" {
    const alloc = std.testing.allocator;
    const rows = try alloc.alloc([][]const u8, 1);
    errdefer alloc.free(rows);
    rows[0] = try alloc.alloc([]const u8, 2);
    errdefer alloc.free(rows[0]);
    rows[0][0] = try alloc.dupe(u8, "a");
    errdefer alloc.free(rows[0][0]);
    rows[0][1] = try alloc.dupe(u8, "b");

    freeCsv(alloc, rows);
}

test "readByte reads a single byte" {
    const fds = try std.posix.pipe();
    defer std.posix.close(fds[0]);
    defer std.posix.close(fds[1]);

    _ = try std.posix.write(fds[1], "z");
    try std.testing.expectEqual(@as(u8, 'z'), try readByte(fds[0]));
}

test "tdebug is callable" {
    tdebug("off {d}", .{1});
    tdebug("on {d}", .{2});
}

const std = @import("std");
const mibu = @import("mibu");
const zig_csv = @import("zig_csv");
