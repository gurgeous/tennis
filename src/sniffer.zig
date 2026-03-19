// Heuristic delimiter sniffer for small CSV/TSV samples.
//
// Overall approach:
// - try a tiny fixed set of candidate delimiters
// - scan the sample line by line
// - count cols for each delim, make sure the sample doesn't look jagged or weird
// - the winner is the delim that works with the sample and has the most cols
//

// Guess a delimiter from a sample, or return null when there is no clear winner.
pub fn sniff(sample: []const u8) ?u8 {
    // early exit if we don't have enough lines, or we see a blank line
    const lines = splitLines(sample);
    if (lines.len < 3) return null;
    for (lines.items[0..lines.len]) |line| {
        if (line.len == 0) return null;
    }

    // put the winner in here
    var best_count: usize = 0;
    var best_delim: ?u8 = null;

    // Candidate delimiters we consider for sniffing. These are in order, the
    // latter ones can only win if they find more cols.
    const candidates = [_]u8{ ',', '\t', ';', '|' };
    for (candidates) |delimiter| {
        const n = countColumns(lines, delimiter);
        if (n > best_count) {
            best_count = n;
            best_delim = delimiter;
        }
    }

    return best_delim;
}

//
// helpers
//

// Up to ten sample rows
const Lines = struct {
    items: [11][]const u8 = undefined,
    len: usize = 0,
};

// Split a sample into Lines
fn splitLines(sample: []const u8) Lines {
    const eol = if (std.mem.indexOf(u8, sample, "\r\n") != null) "\r\n" else "\n";

    // split
    var out: Lines = .{};
    var lines = std.mem.splitSequence(u8, sample, eol);
    while (lines.next()) |line| {
        out.items[out.len] = line;
        out.len += 1;
        if (out.len == out.items.len) break;
    }

    // sample almost always ends mid-line
    if (out.len > 0) out.len -= 1;

    return out;
}

// Count # of cols across these lines. Returns 0 if jagged, nothing found, etc.
fn countColumns(lines: Lines, delimiter: u8) usize {
    var exp: usize = 0;
    for (lines.items[0..lines.len]) |line| {
        const n = countColumnsForLine(line, delimiter);
        if (exp == 0) exp = n; // init
        if (n != exp) return 0; // mismatch?
    }
    if (exp < 2) return 0; // too small?
    return exp;
}

// Count cols in one line
fn countColumnsForLine(line: []const u8, delimiter: u8) usize {
    var n: usize = 1;
    var in_quotes = false;
    var ii: usize = 0;
    while (ii < line.len) : (ii += 1) {
        const ch = line[ii];
        if (ch == '"') {
            // Inside a quoted field, doubled quotes are an escaped literal quote.
            if (in_quotes and ii + 1 < line.len and line[ii + 1] == '"') {
                ii += 1;
            } else {
                in_quotes = !in_quotes;
            }
            continue;
        }
        if (!in_quotes and ch == delimiter) n += 1;
    }
    return n;
}

//
// tests
//

test "sniff success cases" {
    const cases = [_]struct {
        sample: []const u8,
        delimiter: u8,
    }{
        .{ .sample = "a,b,c\n1,2,3\n4,5,6\n7,8", .delimiter = ',' },
        .{ .sample = "a;b;c\n1;2;3\n4;5;6\n7;8", .delimiter = ';' },
        .{ .sample = "a\tb\tc\n1\t2\t3\n4\t5\t6\n7\t8", .delimiter = '\t' },
        .{ .sample = "a|b|c\n1|2|3\n4|5|6\n7|8", .delimiter = '|' },
        .{ .sample = "a,b,c\n\"x,y\",2,3\n\"p,q\",5,6\n\"tail", .delimiter = ',' },
        .{ .sample = "a,b,c\r\n1,2,3\r\n4,5,6\r\n7,8", .delimiter = ',' },
        .{ .sample = "a,b,c,d;|\n1,2,3,4;|\n5,6,7,8;|\n9,10,11,", .delimiter = ',' },
        .{ .sample = "a;b;c;d,|\n1;2;3;4,|\n5;6;7;8,|\n9;10;11;", .delimiter = ';' },
        .{ .sample = "a\tb\tc\td,|\n1\t2\t3\t4,|\n5\t6\t7\t8,|\n9\t10\t11\t", .delimiter = '\t' },
        .{ .sample = "a|b|c|d,;\n1|2|3|4,;\n5|6|7|8,;\n9|10|11|", .delimiter = '|' },
    };

    for (cases) |tc| {
        const got = sniff(tc.sample).?;
        try std.testing.expectEqual(tc.delimiter, got);
    }
}

test "sniff null cases" {
    const cases = [_][]const u8{
        "",
        "a;b\n\n1;2\n",
        "a,b\n1,2\n",
        "hello\nworld\n",
        "a,b,c\n1,2\n",
        "abcdef",
        "a,b,c\n1,2,3",
        "\"a,b,c\n1,2,3\n4,5,6\n",
    };

    for (cases) |sample| {
        try std.testing.expectEqual(@as(?u8, null), sniff(sample));
    }
}

test "sniff uses delimiter priority to break ties" {
    const sample =
        "a;b|c\n" ++
        "1;2|3\n" ++
        "4;5|6\n";
    const got = sniff(sample).?;
    try std.testing.expectEqual(@as(u8, ';'), got);
}

test "sniff rejects jagged rows" {
    try std.testing.expectEqual(@as(?u8, null), sniff("a,b,c\n1,2\n"));
}

test "splitLines cases" {
    const cases = [_]struct {
        sample: []const u8,
        want: []const []const u8,
    }{
        .{ .sample = "", .want = &.{} },
        .{ .sample = "a,b,c", .want = &.{} },
        .{ .sample = "a,b,c\n1,2,3", .want = &.{"a,b,c"} },
        .{ .sample = "a,b,c\n1,2,3\n4,5", .want = &.{ "a,b,c", "1,2,3" } },
        .{ .sample = "a,b,c\r\n1,2,3\r\n4,5", .want = &.{ "a,b,c", "1,2,3" } },
        .{
            .sample = "1\n2\n3\n4\n5\n6\n7\n8\n9\n10\n11\n12",
            .want = &.{ "1", "2", "3", "4", "5", "6", "7", "8", "9", "10" },
        },
    };

    for (cases) |tc| {
        const got = splitLines(tc.sample);
        try std.testing.expectEqual(tc.want.len, got.len);
        for (tc.want, got.items[0..got.len]) |want, line| {
            try std.testing.expectEqualStrings(want, line);
        }
    }
}

test "countColumnsForLine cases" {
    const cases = [_]struct {
        line: []const u8,
        delimiter: u8,
        want: usize,
    }{
        .{ .line = "", .delimiter = ',', .want = 1 },
        .{ .line = "a,b,c", .delimiter = ',', .want = 3 },
        .{ .line = "\"a,b\",c", .delimiter = ',', .want = 2 },
        .{ .line = "\"a\"\"b\",c", .delimiter = ',', .want = 2 },
        .{ .line = "\"a,b,c", .delimiter = ',', .want = 1 },
        .{ .line = "a|b|c", .delimiter = '|', .want = 3 },
    };

    for (cases) |tc| {
        try std.testing.expectEqual(tc.want, countColumnsForLine(tc.line, tc.delimiter));
    }
}

const std = @import("std");
