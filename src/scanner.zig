// Tiny forward-only scanner for byte slices.
pub const Scanner = struct {
    buf: []const u8,
    ii: usize = 0,

    pub fn init(buf: []const u8) Scanner {
        return .{ .buf = buf };
    }

    pub fn next(self: *Scanner) ?u8 {
        if (self.ii >= self.buf.len) return null;
        const ch = self.buf[self.ii];
        self.ii += 1;
        return ch;
    }
};

test "scanner walks a buffer one item at a time" {
    var scan = Scanner.init("ab");
    try std.testing.expectEqual(@as(?u8, 'a'), scan.next());
    try std.testing.expectEqual(@as(?u8, 'b'), scan.next());
    try std.testing.expectEqual(@as(?u8, null), scan.next());
}

const std = @import("std");
