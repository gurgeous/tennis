// Natural string ordering for things like a2 < a10, with special handling for
// leading-zero numeric runs so decimal-like strings sort more sensibly.
//
// Patterned after Martin Pool's natural sort algorithm.
// https://github.com/sourcefrog/natsort

// Compare two strings using natural ordering with optional ASCII case folding.
pub fn order(a_in: []const u8, b_in: []const u8, ignore_case: bool) std.math.Order {
    var a = a_in;
    var b = b_in;

    while (true) {
        a = trimLeadingWhitespace(a);
        b = trimLeadingWhitespace(b);

        if (a.len > 0 and b.len > 0 and isDigit(a[0]) and isDigit(b[0])) {
            // Leading-zero runs behave more like decimal fractions; other runs compare by magnitude.
            const ord = if (a[0] == '0' or b[0] == '0') compareLeft(a, b) else compareRight(a, b);
            if (ord != .eq) return ord;
        }

        if (a.len == 0 and b.len == 0) return .eq;
        if (a.len == 0) return .lt;
        if (b.len == 0) return .gt;
        const a_ch = if (ignore_case) std.ascii.toLower(a[0]) else a[0];
        const b_ch = if (ignore_case) std.ascii.toLower(b[0]) else b[0];
        if (a_ch < b_ch) return .lt;
        if (a_ch > b_ch) return .gt;

        a = a[1..];
        b = b[1..];
    }
}

// Trim only leading ASCII whitespace to match the reference algorithm.
fn trimLeadingWhitespace(text: []const u8) []const u8 {
    var start: usize = 0;
    while (start < text.len and std.ascii.isWhitespace(text[start])) : (start += 1) {}
    return text[start..];
}

// Compare digit runs left-aligned so leading zeros remain significant.
fn compareLeft(a_in: []const u8, b_in: []const u8) std.math.Order {
    var a = a_in;
    var b = b_in;

    while (true) {
        const a_digit = a.len > 0 and isDigit(a[0]);
        const b_digit = b.len > 0 and isDigit(b[0]);

        if (!a_digit and !b_digit) return .eq;
        if (!a_digit) return .lt;
        if (!b_digit) return .gt;
        if (a[0] < b[0]) return .lt;
        if (a[0] > b[0]) return .gt;

        a = a[1..];
        b = b[1..];
    }
}

// Compare digit runs by magnitude, falling back to first differing digit as bias.
fn compareRight(a_in: []const u8, b_in: []const u8) std.math.Order {
    var a = a_in;
    var b = b_in;
    var bias: std.math.Order = .eq;

    while (true) {
        const a_digit = a.len > 0 and isDigit(a[0]);
        const b_digit = b.len > 0 and isDigit(b[0]);

        if (!a_digit and !b_digit) return bias;
        if (!a_digit) return .lt;
        if (!b_digit) return .gt;
        if (bias == .eq) {
            if (a[0] < b[0]) bias = .lt;
            if (a[0] > b[0]) bias = .gt;
        }

        a = a[1..];
        b = b[1..];
    }
}

//
// testing
//

test "plain strings" {
    try testing.expectEqual(std.math.Order.lt, order("a", "b", false));
    try testing.expectEqual(std.math.Order.gt, order("b", "a", false));
    try testing.expectEqual(std.math.Order.eq, order("abc", "abc", false));
    try testing.expectEqual(std.math.Order.eq, order("abc", "ABC", true));
    try testing.expectEqual(std.math.Order.lt, order("a", "B", true));
    try testing.expectEqual(std.math.Order.gt, order("B", "a", true));
}

test "simple numeric runs" {
    try testing.expectEqual(std.math.Order.lt, order("a2", "a10", false));
    try testing.expectEqual(std.math.Order.lt, order("rfc1.txt", "rfc822.txt", false));
    try testing.expectEqual(std.math.Order.lt, order("rfc822.txt", "rfc2086.txt", false));
    try testing.expectEqual(std.math.Order.lt, order("A2", "a10", true));
    try testing.expectEqual(std.math.Order.eq, order("RFC1.txt", "rfc1.TXT", true));
}

test "pure numeric strings" {
    try testing.expectEqual(std.math.Order.lt, order("9", "10", false));
    try testing.expectEqual(std.math.Order.lt, order("2", "100", false));
    try testing.expectEqual(std.math.Order.gt, order("100", "2", false));
}

test "multiple numeric runs" {
    try testing.expectEqual(std.math.Order.lt, order("x2-g8", "x2-y08", false));
    try testing.expectEqual(std.math.Order.lt, order("x2-y08", "x2-y7", false));
    try testing.expectEqual(std.math.Order.lt, order("x2-y7", "x8-y8", false));
}

test "fractional-looking strings with leading zeros" {
    const vals = [_][]const u8{ "1.001", "1.002", "1.010", "1.02", "1.1", "1.3" };
    for (vals[0 .. vals.len - 1], vals[1..]) |a, b| {
        try testing.expectEqual(std.math.Order.lt, order(a, b, false));
    }
}

test "leading whitespace" {
    try testing.expectEqual(std.math.Order.eq, order("  a2", "a2", false));
    try testing.expectEqual(std.math.Order.lt, order("  a2", "a10", false));
}

test "negative signs as plain characters" {
    // This is a string-oriented comparator, not numeric parsing, so "-5" sorts before "-10".
    try testing.expectEqual(std.math.Order.lt, order("-5", "-10", false));
}

const isDigit = @import("std").ascii.isDigit;
const std = @import("std");
const testing = std.testing;
