pub fn formatInt(alloc: std.mem.Allocator, s: []const u8) ![]u8 {
    if (s.len == 0) return alloc.dupe(u8, s);

    const width = intWidth(s);
    if (width == s.len) return alloc.dupe(u8, s);

    const out = try alloc.alloc(u8, width);
    var src = s.len;
    var dst = out.len;
    var seen_digits: usize = 0;
    while (src > 0 and std.ascii.isDigit(s[src - 1])) {
        dst -= 1;
        out[dst] = s[src - 1];
        src -= 1;
        seen_digits += 1;
        if (src > 0 and seen_digits % 3 == 0 and std.ascii.isDigit(s[src - 1])) {
            dst -= 1;
            out[dst] = ',';
        }
    }
    if (src > 0) out[0] = '-';
    return out;
}

fn intWidth(s: []const u8) usize {
    if (s.len == 0) return 0;
    const off: usize = if (s[0] == '-') 1 else 0;
    const ndigits = s.len - off;
    if (ndigits <= 3) return s.len;
    return s.len + (ndigits - 1) / 3;
}

test "intWidth" {
    try std.testing.expectEqual(@as(usize, 0), intWidth(""));
    try std.testing.expectEqual(@as(usize, 1), intWidth("0"));
    try std.testing.expectEqual(@as(usize, 3), intWidth("123"));
    try std.testing.expectEqual(@as(usize, 5), intWidth("1234"));
    try std.testing.expectEqual(@as(usize, 6), intWidth("-1234"));
    try std.testing.expectEqual(@as(usize, 9), intWidth("1234567"));
    try std.testing.expectEqual(@as(usize, 10), intWidth("-1234567"));
}

test "formatInt" {
    const cases = [_]struct {
        in: []const u8,
        want: []const u8,
    }{
        .{ .in = "0", .want = "0" },
        .{ .in = "1", .want = "1" },
        .{ .in = "-1", .want = "-1" },
        .{ .in = "10", .want = "10" },
        .{ .in = "-10", .want = "-10" },
        .{ .in = "1234", .want = "1,234" },
        .{ .in = "-1234567", .want = "-1,234,567" },
    };

    for (cases) |case| {
        const got = try formatInt(std.testing.allocator, case.in);
        defer std.testing.allocator.free(got);
        try std.testing.expectEqualStrings(case.want, got);
    }
}

const std = @import("std");
