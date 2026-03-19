// Reader adapter that buffers and replays an initial buf before continuing
// with the nested reader.
pub fn ReplayReader(comptime Reader: type) type {
    return struct {
        alloc: std.mem.Allocator,
        inner: Reader,
        buf: []u8,
        len: usize = 0,
        ii: usize = 0,
        pending_error: ?Error = null,

        const Self = @This();
        pub const Error = anyerror;
        pub const ReaderType = std.io.GenericReader(*Self, Error, read);

        // Read and own up to `nbytes` from the nested reader for replay/sniffing.
        pub fn init(alloc: std.mem.Allocator, inner: Reader, nbytes: usize) !Self {
            const buf = try alloc.alloc(u8, nbytes);
            errdefer alloc.free(buf);

            var pending_error: ?Error = null;
            var len: usize = 0;
            while (len < buf.len) {
                const n = inner.read(buf[len..]) catch |err| {
                    pending_error = err;
                    break;
                };
                if (n == 0) break;
                len += n;
            }

            return .{
                .alloc = alloc,
                .inner = inner,
                .buf = buf,
                .len = len,
                .pending_error = pending_error,
            };
        }

        // Free the owned replay buffer.
        pub fn deinit(self: Self) void {
            self.alloc.free(self.buf);
        }

        // Return the saved buf for sniffing or inspection.
        pub fn buffer(self: *const Self) []const u8 {
            return self.buf[0..self.len];
        }

        // Return a standard Zig reader suitable
        pub fn reader(self: *Self) ReaderType {
            return .{ .context = self };
        }

        // Read from the saved buf first, then continue with the nested reader.
        pub fn read(self: *Self, dest: []u8) Error!usize {
            if (dest.len == 0) return 0;

            var written: usize = 0;
            if (self.ii < self.len) {
                const n = @min(dest.len, self.len - self.ii);
                @memcpy(dest[0..n], self.buf[self.ii .. self.ii + n]);
                self.ii += n;
                written += n;
                if (written == dest.len) return written;
            }

            if (self.pending_error) |err| {
                if (written > 0) return written;
                self.pending_error = null;
                return err;
            }

            const n = self.inner.read(dest[written..]) catch |err| {
                if (written > 0) {
                    self.pending_error = err;
                    return written;
                }
                return err;
            };
            return written + n;
        }
    };
}

//
// tests
//

test "ReplayReader buffers and replays buf" {
    const alloc = std.testing.allocator;
    var inner = std.io.fixedBufferStream("abcdef");
    var replay = try ReplayReader(@TypeOf(inner.reader())).init(alloc, inner.reader(), 3);
    defer replay.deinit();

    try std.testing.expectEqualStrings("abc", replay.buffer());

    var buf: [8]u8 = undefined;
    const n = try replay.reader().readAll(&buf);
    try std.testing.expectEqual(@as(usize, 6), n);
    try std.testing.expectEqualStrings("abcdef", buf[0..n]);
}

test "ReplayReader works across small chunked reads" {
    const alloc = std.testing.allocator;
    var inner = std.io.fixedBufferStream("123456");
    var replay = try ReplayReader(@TypeOf(inner.reader())).init(alloc, inner.reader(), 3);
    defer replay.deinit();
    var reader = replay.reader();

    var buf: [2]u8 = undefined;

    var n = try reader.read(&buf);
    try std.testing.expectEqual(@as(usize, 2), n);
    try std.testing.expectEqualStrings("12", buf[0..n]);

    n = try reader.read(&buf);
    try std.testing.expectEqual(@as(usize, 2), n);
    try std.testing.expectEqualStrings("34", buf[0..n]);

    n = try reader.read(&buf);
    try std.testing.expectEqual(@as(usize, 2), n);
    try std.testing.expectEqualStrings("56", buf[0..n]);

    n = try reader.read(&buf);
    try std.testing.expectEqual(@as(usize, 0), n);
}

test "ReplayReader handles short input" {
    const alloc = std.testing.allocator;
    var inner = std.io.fixedBufferStream("xy");
    var replay = try ReplayReader(@TypeOf(inner.reader())).init(alloc, inner.reader(), 4);
    defer replay.deinit();

    try std.testing.expectEqualStrings("xy", replay.buffer());

    var buf: [8]u8 = undefined;
    const n = try replay.reader().readAll(&buf);
    try std.testing.expectEqual(@as(usize, 2), n);
    try std.testing.expectEqualStrings("xy", buf[0..n]);
}

test "ReplayReader handles zero-byte buffer" {
    const alloc = std.testing.allocator;
    var inner = std.io.fixedBufferStream("xyz");
    var replay = try ReplayReader(@TypeOf(inner.reader())).init(alloc, inner.reader(), 0);
    defer replay.deinit();

    try std.testing.expectEqualStrings("", replay.buffer());

    var buf: [8]u8 = undefined;
    const n = try replay.reader().readAll(&buf);
    try std.testing.expectEqual(@as(usize, 3), n);
    try std.testing.expectEqualStrings("xyz", buf[0..n]);
}

test "ReplayReader zero-length read does nothing" {
    const alloc = std.testing.allocator;
    var inner = std.io.fixedBufferStream("abc");
    var replay = try ReplayReader(@TypeOf(inner.reader())).init(alloc, inner.reader(), 2);
    defer replay.deinit();
    var reader = replay.reader();

    var buf: [0]u8 = undefined;
    const n = try reader.read(&buf);
    try std.testing.expectEqual(@as(usize, 0), n);
    try std.testing.expectEqualStrings("ab", replay.buffer());
}

test "ReplayReader preserves buffered bytes when init hits a read error" {
    const alloc = std.testing.allocator;
    var inner: FailingReader = .{ .input = "abcdef", .fail_at = 2 };
    var replay = try ReplayReader(FailingReader.ReaderType).init(alloc, inner.reader(), 4);
    defer replay.deinit();

    try std.testing.expectEqualStrings("ab", replay.buffer());

    var buf: [8]u8 = undefined;
    var reader = replay.reader();

    const n = try reader.read(&buf);
    try std.testing.expectEqual(@as(usize, 2), n);
    try std.testing.expectEqualStrings("ab", buf[0..n]);

    try std.testing.expectError(error.Boom, reader.read(&buf));
}

test "ReplayReader returns replayed bytes before surfacing later inner error" {
    const alloc = std.testing.allocator;
    var inner: FailingReader = .{ .input = "cdef", .fail_at = 2 };
    var replay = try ReplayReader(FailingReader.ReaderType).init(alloc, inner.reader(), 2);
    defer replay.deinit();
    var reader = replay.reader();

    var buf: [4]u8 = undefined;
    const n = try reader.read(&buf);
    try std.testing.expectEqual(@as(usize, 2), n);
    try std.testing.expectEqualStrings("cd", buf[0..n]);

    try std.testing.expectError(error.Boom, reader.read(&buf));
}

test "ReplayReader surfaces deferred error once buffer is exhausted" {
    const alloc = std.testing.allocator;
    var inner: FailingReader = .{ .input = "abc", .fail_at = 1 };
    var replay = try ReplayReader(FailingReader.ReaderType).init(alloc, inner.reader(), 2);
    defer replay.deinit();
    var reader = replay.reader();

    var buf: [4]u8 = undefined;
    const n = try reader.read(&buf);
    try std.testing.expectEqual(@as(usize, 1), n);
    try std.testing.expectEqualStrings("a", buf[0..n]);

    try std.testing.expectError(error.Boom, reader.read(&buf));
}

const FailingReader = struct {
    input: []const u8,
    ii: usize = 0,
    fail_at: usize,

    const Self = @This();
    const ReaderType = std.io.GenericReader(*Self, anyerror, read);

    fn reader(self: *Self) ReaderType {
        return .{ .context = self };
    }

    fn read(self: *Self, dest: []u8) anyerror!usize {
        if (self.ii >= self.fail_at) return error.Boom;

        const max_n = @min(dest.len, self.fail_at - self.ii);
        const avail = @min(max_n, self.input.len - self.ii);
        if (avail == 0) return 0;

        @memcpy(dest[0..avail], self.input[self.ii .. self.ii + avail]);
        self.ii += avail;
        return avail;
    }
};

const std = @import("std");
