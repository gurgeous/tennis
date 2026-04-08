// Integer detection and formatting helpers for numeric columns.
// Report whether a byte slice looks like a simple integer literal.
pub fn isInt(str: []const u8) bool {
    var scan = Scanner.init(str);
    _ = scan.scanCh('-'); // skip neg
    return scan.scanDigits() > 0 and scan.eos();
}

// Format an integer string with thousands separators.
pub fn intFormat(alloc: std.mem.Allocator, str: []const u8) ![]u8 {
    // Small ints do not need separators. This is common.
    const width = intWidth(str);
    if (width == str.len) return alloc.dupe(u8, str);

    // gotta add delims, which requires a bigger buffer
    const out = try alloc.alloc(u8, width);
    formatInto(out, str);
    return out;
}

// Write an integer string into a pre-sized output buffer.
pub fn formatInto(out: []u8, str: []const u8) void {
    if (str.len == 0) return;
    const neg = str[0] == '-';
    if (neg) out[0] = '-';
    const digits = if (neg) str[1..] else str;

    // Fill from the right so we can add commas every 3 digits.
    var src = digits.len;
    var dst = out.len;
    var n: usize = 0;
    while (src > 0) {
        src -= 1;
        dst -= 1;
        out[dst] = digits[src];

        // maybe a comma?
        n += 1;
        if (src > 0 and n % 3 == 0) {
            dst -= 1;
            out[dst] = ',';
        }
    }
}

// Compute the display width of an int with separators.
pub fn intWidth(s: []const u8) usize {
    if (s.len == 0) return 0;
    const off: usize = if (s[0] == '-') 1 else 0;
    const ndigits = s.len - off;
    if (ndigits <= 3) return s.len;
    return s.len + (ndigits - 1) / 3;
}

//
// testing
//

test "intWidth" {
    try testing.expectEqual(@as(usize, 0), intWidth(""));
    try testing.expectEqual(@as(usize, 1), intWidth("0"));
    try testing.expectEqual(@as(usize, 3), intWidth("123"));
    try testing.expectEqual(@as(usize, 5), intWidth("1234"));
    try testing.expectEqual(@as(usize, 6), intWidth("-1234"));
    try testing.expectEqual(@as(usize, 9), intWidth("1234567"));
    try testing.expectEqual(@as(usize, 10), intWidth("-1234567"));
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
        const act = try intFormat(testing.allocator, case.in);
        defer testing.allocator.free(act);
        try testing.expectEqualStrings(case.exp, act);
    }
}

test "formatInto handles empty input" {
    var out: [0]u8 = undefined;
    formatInto(&out, "");
}

test "isInt" {
    const cases = [_]struct {
        input: []const u8,
        want: bool,
    }{
        .{ .input = "0", .want = true },
        .{ .input = "123", .want = true },
        .{ .input = "-123", .want = true },
        .{ .input = "", .want = false },
        .{ .input = "-", .want = false },
        .{ .input = "1.0", .want = false },
        .{ .input = "+1", .want = false },
        .{ .input = "1e6", .want = false },
        .{ .input = "abc", .want = false },
    };

    for (cases) |tc| {
        try testing.expectEqual(tc.want, isInt(tc.input));
    }
}

const Scanner = @import("scanner.zig").Scanner;
const std = @import("std");
const testing = std.testing;
