// Match -?\d+\.\d+
pub fn isFloat(slice: []const u8) bool {
    // Keep obviously huge numeric-looking cells out of the float formatter.
    if (slice.len > max_float_len) return false;
    var scan = Scanner.init(slice);
    _ = scan.scanCh('-'); // skip neg
    if (scan.scanDigits() == 0) return false; // whole
    if (!scan.scanCh('.')) return false; // dot
    return scan.scanDigits() > 0 and scan.done(); // frac
}

// format s as a delimited float rounded to three decimals
pub fn floatFormat(alloc: std.mem.Allocator, s: []const u8) ![]u8 {
    if (s.len == 0) return alloc.dupe(u8, s);
    var buf: [max_float_len]u8 = undefined;
    // Round first, then add delimiters only to the whole-number part.
    const rounded = try std.fmt.bufPrint(&buf, "{d:.3}", .{try std.fmt.parseFloat(f64, s)});
    const dot = std.mem.indexOfScalar(u8, rounded, '.') orelse return alloc.dupe(u8, rounded);
    const whole = rounded[0..dot];
    const frac = rounded[dot..];
    const whole_width = int.intWidth(whole);
    const out = try alloc.alloc(u8, whole_width + frac.len);
    int.formatInto(out[0..whole_width], whole);
    @memcpy(out[whole_width..], frac);
    return out;
}

const max_float_len = 64;

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
    try std.testing.expect(!isFloat("1.0b"));
    try std.testing.expect(!isFloat(".5"));
    try std.testing.expect(!isFloat("-.5"));
    try std.testing.expect(!isFloat("1e6"));
    try std.testing.expect(!isFloat("1.2.3"));
    try std.testing.expect(!isFloat("+1.0"));
    try std.testing.expect(!isFloat("12345678901234567890123456789012345678901234567890123456789012345.0"));
}

const int = @import("int.zig");
const Scanner = @import("scanner.zig").Scanner;
const std = @import("std");
