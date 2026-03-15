const max_float_len = 64;

// Does this str contain a float? -?\d+\.\d+
pub fn isFloat(str: []const u8) bool {
    // Keep obviously huge numeric-looking cells out of the float formatter.
    if (str.len > max_float_len) return false;
    var scan = Scanner.init(str);
    _ = scan.scanCh('-'); // neg, maybe
    if (scan.scanDigits() == 0) return false; // whole
    if (!scan.scanCh('.')) return false; // dot
    return scan.scanDigits() > 0 and scan.eos(); // fract
}

// Format str as a delimited float truncated to ndecimals.
pub fn floatFormat(alloc: std.mem.Allocator, str: []const u8, ndecimals: usize) ![]u8 {
    if (str.len == 0) return alloc.dupe(u8, str);
    // divide up into whole/fract
    const dot = std.mem.indexOfScalar(u8, str, '.');
    const whole = if (dot) |ii| str[0..ii] else str;
    const fract = if (dot) |ii| str[ii + 1 ..] else "";
    const whole_width = int.intWidth(whole);
    const out = try alloc.alloc(u8, whole_width + 1 + ndecimals);

    // whole
    var ii: usize = 0;
    int.formatInto(out[0..whole_width], whole);
    ii += whole_width;

    // dot
    out[ii] = '.';
    ii += 1;

    // fract
    const copy_len = @min(fract.len, ndecimals);
    @memset(out[ii .. ii + ndecimals], '0');
    @memcpy(out[ii..][0..copy_len], fract[0..copy_len]);
    return out;
}

test "floatFormat" {
    const cases = [_]struct {
        in: []const u8,
        exp: []const u8,
    }{
        .{ .in = "", .exp = "" },
        .{ .in = "4", .exp = "4.000" },
        .{ .in = "0.0", .exp = "0.000" },
        .{ .in = "1.0", .exp = "1.000" },
        .{ .in = "-1.0", .exp = "-1.000" },
        .{ .in = "10.0", .exp = "10.000" },
        .{ .in = "-10.0", .exp = "-10.000" },
        .{ .in = "1234.0", .exp = "1,234.000" },
        .{ .in = "-1234567.8912", .exp = "-1,234,567.891" },
        .{ .in = "12.34567", .exp = "12.345" },
        .{ .in = "0.9996", .exp = "0.999" },
        .{ .in = "999.9995", .exp = "999.999" },
    };

    for (cases) |case| {
        const act = try floatFormat(std.testing.allocator, case.in, 3);
        defer std.testing.allocator.free(act);
        try std.testing.expectEqualStrings(case.exp, act);
    }
}

test "floatFormat uses requested digits" {
    const act = try floatFormat(std.testing.allocator, "12.34567", 1);
    defer std.testing.allocator.free(act);
    try std.testing.expectEqualStrings("12.3", act);
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
