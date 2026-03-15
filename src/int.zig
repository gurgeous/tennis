// Match -?\d+
pub fn isInt(slice: []const u8) bool {
    var scan = Scanner.init(slice);
    var ch = scan.next() orelse return false;
    if (ch == '-') ch = scan.next() orelse return false;
    if (!std.ascii.isDigit(ch)) return false;

    while (scan.next()) |next_ch| {
        if (!std.ascii.isDigit(next_ch)) return false;
    }
    return true;
}

// format s as a delimited int
pub fn intFormat(alloc: std.mem.Allocator, s: []const u8) ![]u8 {
    // in many cases we don't have to do anything at all
    const width = intWidth(s);
    if (width == s.len) return alloc.dupe(u8, s);
    const out = try alloc.alloc(u8, width);

    const neg = s[0] == '-';
    if (neg) out[0] = '-';

    const digits = if (neg) s[1..] else s;
    var src = digits.len;
    var dst = out.len;
    var n: usize = 0;
    while (src > 0) {
        src -= 1;
        dst -= 1;
        out[dst] = digits[src];
        // maybe a comma
        n += 1;
        if (src > 0 and n % 3 == 0) {
            dst -= 1;
            out[dst] = ',';
        }
    }
    return out;
}

// calculate how big a buf we need to format an int with delims
pub fn intWidth(s: []const u8) usize {
    if (s.len == 0) return 0;
    const off: usize = if (s[0] == '-') 1 else 0;
    const ndigits = s.len - off;
    if (ndigits <= 3) return s.len;
    return s.len + (ndigits - 1) / 3;
}

//
// tests
//

test "intWidth" {
    try std.testing.expectEqual(@as(usize, 0), intWidth(""));
    try std.testing.expectEqual(@as(usize, 1), intWidth("0"));
    try std.testing.expectEqual(@as(usize, 3), intWidth("123"));
    try std.testing.expectEqual(@as(usize, 5), intWidth("1234"));
    try std.testing.expectEqual(@as(usize, 6), intWidth("-1234"));
    try std.testing.expectEqual(@as(usize, 9), intWidth("1234567"));
    try std.testing.expectEqual(@as(usize, 10), intWidth("-1234567"));
}

test "intFormat" {
    const cases = [_]struct {
        in: []const u8,
        exp: []const u8,
    }{
        .{ .in = "0", .exp = "0" },
        .{ .in = "1", .exp = "1" },
        .{ .in = "-1", .exp = "-1" },
        .{ .in = "10", .exp = "10" },
        .{ .in = "-10", .exp = "-10" },
        .{ .in = "1234", .exp = "1,234" },
        .{ .in = "-1234567", .exp = "-1,234,567" },
    };

    for (cases) |case| {
        const act = try intFormat(std.testing.allocator, case.in);
        defer std.testing.allocator.free(act);
        try std.testing.expectEqualStrings(case.exp, act);
    }
}

test "isInt" {
    try std.testing.expect(isInt("0"));
    try std.testing.expect(isInt("123"));
    try std.testing.expect(isInt("-123"));
    try std.testing.expect(!isInt(""));
    try std.testing.expect(!isInt("-"));
    try std.testing.expect(!isInt("1.0"));
    try std.testing.expect(!isInt("+1"));
    try std.testing.expect(!isInt("1e6"));
    try std.testing.expect(!isInt("abc"));
}

const Scanner = @import("scanner.zig").Scanner;
const std = @import("std");
