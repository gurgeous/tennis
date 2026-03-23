// Tiny forward-only scanner for byte slices.
pub const Scanner = struct {
    buf: []const u8,
    ii: usize = 0,

    // Build a scanner over one byte slice.
    pub fn init(buf: []const u8) Scanner {
        return .{ .buf = buf };
    }

    // take a peek at next char, but don't consume it
    pub fn peek(self: *const Scanner) ?u8 {
        if (self.eos()) return null;
        return self.buf[self.ii];
    }

    // get next char, if any
    pub fn next(self: *Scanner) ?u8 {
        const ch = self.peek() orelse return null;
        self.ii += 1;
        return ch;
    }

    // scan (consume) a specific char, returns true if scanned
    pub fn scanCh(self: *Scanner, ch: u8) bool {
        const nxt = self.peek() orelse return false;
        if (nxt != ch) return false;
        self.ii += 1;
        return true;
    }

    // scan (consume) 1+ digits
    pub fn scanDigits(self: *Scanner) usize {
        var n: usize = 0;
        while (self.peek()) |ch| {
            if (!std.ascii.isDigit(ch)) break;
            self.ii += 1;
            n += 1;
        }
        return n;
    }

    // Report whether the scanner is at end of input.
    pub fn eos(self: *const Scanner) bool {
        return self.ii == self.buf.len;
    }
};

//
// testing
//

test "scanner walks a buffer one item at a time" {
    var scan = Scanner.init("ab");
    try testing.expectEqual(@as(?u8, 'a'), scan.peek());
    try testing.expectEqual(@as(?u8, 'a'), scan.next());
    try testing.expectEqual(@as(?u8, 'b'), scan.peek());
    try testing.expectEqual(@as(?u8, 'b'), scan.next());
    try testing.expectEqual(@as(?u8, null), scan.peek());
    try testing.expectEqual(@as(?u8, null), scan.next());
}

test "scanCh consumes only a matching char" {
    var scan = Scanner.init("-12");
    try testing.expect(scan.scanCh('-'));
    try testing.expectEqual(@as(?u8, '1'), scan.peek());
    try testing.expect(!scan.scanCh('-'));
    try testing.expectEqual(@as(?u8, '1'), scan.peek());
}

test "scanDigits consumes only digits" {
    var scan = Scanner.init("123x");
    try testing.expectEqual(@as(usize, 3), scan.scanDigits());
    try testing.expectEqual(@as(?u8, 'x'), scan.peek());
    try testing.expectEqual(@as(?u8, 'x'), scan.next());
}

test "eos reports only true end of stream" {
    var scan = Scanner.init("1.");
    try testing.expect(!scan.eos());
    try testing.expectEqual(@as(usize, 1), scan.scanDigits());
    try testing.expect(!scan.eos());
    try testing.expect(scan.scanCh('.'));
    try testing.expect(scan.eos());
}

const std = @import("std");
const testing = std.testing;
