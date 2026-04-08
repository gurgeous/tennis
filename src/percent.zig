// Percent detection and formatting helpers for percent-like columns.

// Report whether a byte slice looks like a strict percent literal.
pub fn isPercent(str: []const u8) bool {
    var scan = Scanner.init(str);
    _ = scan.scanCh('-');
    if (scan.scanDigits() == 0) return false;
    if (scan.scanCh('.')) {
        if (scan.scanDigits() == 0) return false;
    }
    return scan.scanCh('%') and scan.eos();
}

//
// testing
//

test "isPercent" {
    const cases = [_]struct {
        input: []const u8,
        want: bool,
    }{
        .{ .input = "0%", .want = true },
        .{ .input = "12%", .want = true },
        .{ .input = "-12%", .want = true },
        .{ .input = "12.5%", .want = true },
        .{ .input = "-0.5%", .want = true },
        .{ .input = "", .want = false },
        .{ .input = "%", .want = false },
        .{ .input = "12", .want = false },
        .{ .input = "12 %", .want = false },
        .{ .input = " 12%", .want = false },
        .{ .input = "+12%", .want = false },
        .{ .input = "12.%", .want = false },
        .{ .input = ".5%", .want = false },
        .{ .input = "12.5", .want = false },
        .{ .input = "abc%", .want = false },
    };

    for (cases) |tc| {
        try testing.expectEqual(tc.want, isPercent(tc.input));
    }
}

const Scanner = @import("scanner.zig").Scanner;
const std = @import("std");
const testing = std.testing;
