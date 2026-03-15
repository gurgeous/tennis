// Tiny forward-only scanner for byte slices.
pub const Scanner = struct {
    buf: []const u8,
    ii: usize = 0,

    pub fn init(buf: []const u8) Scanner {
        return .{ .buf = buf };
    }

    pub fn peek(self: *const Scanner) ?u8 {
        if (self.done()) return null;
        return self.buf[self.ii];
    }

    pub fn next(self: *Scanner) ?u8 {
        const ch = self.peek() orelse return null;
        self.ii += 1;
        return ch;
    }

    // scan a specific char, returns true if scanned
    pub fn scanCh(self: *Scanner, ch: u8) bool {
        const nxt = self.peek() orelse return false;
        if (nxt != ch) return false;
        self.ii += 1;
        return true;
    }

    // scan 1+ digits
    pub fn scanDigits(self: *Scanner) usize {
        var n: usize = 0;
        while (self.next()) |ch| {
            if (!std.ascii.isDigit(ch)) break;
            n += 1;
        }
        return n;
    }

    pub fn done(self: *const Scanner) bool {
        return self.ii == self.buf.len;
    }
};

test "scanner walks a buffer one item at a time" {
    var scan = Scanner.init("ab");
    try std.testing.expectEqual(@as(?u8, 'a'), scan.peek());
    try std.testing.expectEqual(@as(?u8, 'a'), scan.next());
    try std.testing.expectEqual(@as(?u8, 'b'), scan.peek());
    try std.testing.expectEqual(@as(?u8, 'b'), scan.next());
    try std.testing.expectEqual(@as(?u8, null), scan.peek());
    try std.testing.expectEqual(@as(?u8, null), scan.next());
}

const std = @import("std");
