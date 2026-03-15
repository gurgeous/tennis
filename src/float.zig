// Match -?\d+\.\d+
pub fn isFloat(slice: []const u8) bool {
    var scan = Scanner.init(slice);
    var ch = scan.next() orelse return false;
    if (ch == '-') ch = scan.next() orelse return false;
    if (!std.ascii.isDigit(ch)) return false;

    while (scan.next()) |next_ch| {
        if (std.ascii.isDigit(next_ch)) continue;
        if (next_ch != '.') return false;

        var saw_frac_digit = false;
        while (scan.next()) |frac_ch| {
            if (!std.ascii.isDigit(frac_ch)) return false;
            saw_frac_digit = true;
        }
        return saw_frac_digit;
    }
    return false;
}

// format s as a delimited float rounded to three decimals
pub fn floatFormat(alloc: std.mem.Allocator, s: []const u8) ![]u8 {
    if (s.len == 0) return alloc.dupe(u8, s);
    var buf: [128]u8 = undefined;
    const rounded = try std.fmt.bufPrint(&buf, "{d:.3}", .{try std.fmt.parseFloat(f64, s)});
    const dot = std.mem.indexOfScalar(u8, rounded, '.') orelse return int.intFormat(alloc, rounded);
    const whole = try int.intFormat(alloc, rounded[0..dot]);
    defer alloc.free(whole);
    return std.fmt.allocPrint(alloc, "{s}{s}", .{ whole, rounded[dot..] });
}

// calculate how big a buf we need to format a float with delims and precision
pub fn floatWidth(s: []const u8) !usize {
    if (s.len == 0) return 0;
    var buf: [128]u8 = undefined;
    const rounded = try std.fmt.bufPrint(&buf, "{d:.3}", .{try std.fmt.parseFloat(f64, s)});
    const dot = std.mem.indexOfScalar(u8, rounded, '.') orelse return int.intWidth(rounded);
    return int.intWidth(rounded[0..dot]) + rounded[dot..].len;
}

test "floatWidth" {
    try std.testing.expectEqual(@as(usize, 5), try floatWidth("1.0"));
    try std.testing.expectEqual(@as(usize, 6), try floatWidth("-1.0"));
    try std.testing.expectEqual(@as(usize, 9), try floatWidth("1234.567"));
    try std.testing.expectEqual(@as(usize, 10), try floatWidth("-1234.567"));
    try std.testing.expectEqual(@as(usize, 13), try floatWidth("1234567.8912"));
}

test "floatFormat" {
    const cases = [_]struct {
        in: []const u8,
        exp: []const u8,
    }{
        .{ .in = "0.0", .exp = "0.000" },
        .{ .in = "1.0", .exp = "1.000" },
        .{ .in = "-1.0", .exp = "-1.000" },
        .{ .in = "10.0", .exp = "10.000" },
        .{ .in = "-10.0", .exp = "-10.000" },
        .{ .in = "1234.0", .exp = "1,234.000" },
        .{ .in = "-1234567.8912", .exp = "-1,234,567.891" },
        .{ .in = "12.34567", .exp = "12.346" },
    };

    for (cases) |case| {
        const act = try floatFormat(std.testing.allocator, case.in);
        defer std.testing.allocator.free(act);
        try std.testing.expectEqualStrings(case.exp, act);
    }
}

test "isFloat" {
    try std.testing.expect(isFloat("1.0"));
    try std.testing.expect(isFloat("-1.0"));
    try std.testing.expect(isFloat("12.34"));
    try std.testing.expect(!isFloat(""));
    try std.testing.expect(!isFloat("1"));
    try std.testing.expect(!isFloat("1."));
    try std.testing.expect(!isFloat(".5"));
    try std.testing.expect(!isFloat("-.5"));
    try std.testing.expect(!isFloat("1e6"));
    try std.testing.expect(!isFloat("1.2.3"));
    try std.testing.expect(!isFloat("+1.0"));
}

const int = @import("int.zig");
const Scanner = @import("scanner.zig").Scanner;
const std = @import("std");
