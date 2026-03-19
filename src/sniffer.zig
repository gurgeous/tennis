// Heuristic delimiter sniffer for small CSV/TSV samples.
//
// Overall approach:
// - try a tiny fixed set of candidate delimiters
// - scan the sample line by line
// - count fields for each candidate, ignoring delimiters inside double quotes
// - prefer delimiters that produce the same multi-field row shape repeatedly
//
// This is intentionally much simpler than Python's csv.Sniffer. It only tries
// to guess the delimiter, and only from a small set that makes sense for this
// app: comma, semicolon, tab, and pipe.

// Candidate delimiters we consider for sniffing.
pub const default_delimiters = [_]u8{ ',', ';', '\t', '|' };

// Result of delimiter sniffing.
pub const Result = struct {
    delimiter: u8,
    fields: usize,
    rows: usize,
};

// Up to ten complete sample rows kept on the stack.
const Lines = struct {
    items: [11][]const u8 = undefined,
    len: usize = 0,

    // Return the populated prefix of sampled rows.
    fn slice(self: *const Lines) []const []const u8 {
        return self.items[0..self.len];
    }
};

// Guess a delimiter from a sample, or return null when there is no clear winner.
pub fn sniff(sample: []const u8) ?Result {
    const lines = splitLines(sample);
    if (lines.len < 3) return null;

    var best: ?Score = null;
    for (default_delimiters) |delimiter| {
        const score = scoreDelimiter(lines.slice(), delimiter);
        if (score.rows == 0) continue;
        if (best == null or better(score, best.?)) best = score;
    }
    if (best) |score| {
        if (score.fields < 2) return null;
        return .{
            .delimiter = score.delimiter,
            .fields = score.fields,
            .rows = score.rows,
        };
    }
    return null;
}

// Internal candidate score for one delimiter.
const Score = struct {
    // Candidate delimiter byte.
    delimiter: u8,
    // Expected field count for every non-empty row in the sample.
    fields: usize,
    // Number of rows that matched the expected field count.
    rows: usize,
};

// Score one delimiter by enforcing the same row shape across prepared sample lines.
fn scoreDelimiter(lines: []const []const u8, delimiter: u8) Score {
    var expected_fields: ?usize = null;
    var rows: usize = 0;

    for (lines) |line| {
        if (!processLine(line, delimiter, &expected_fields, &rows)) {
            return .{ .delimiter = delimiter, .fields = 0, .rows = 0 };
        }
    }

    return .{
        .delimiter = delimiter,
        .fields = expected_fields orelse 0,
        .rows = rows,
    };
}

// Split a sample into at most ten complete logical rows.
fn splitLines(sample: []const u8) Lines {
    const eol = if (std.mem.indexOf(u8, sample, "\r\n") != null) "\r\n" else "\n";
    var out: Lines = .{};

    var lines = std.mem.splitSequence(u8, sample, eol);
    while (lines.next()) |line| {
        if (out.len == out.items.len) break;
        out.items[out.len] = line;
        out.len += 1;
    }

    // Always drop the final split chunk because sampled input may end mid-line.
    if (out.len == 0) return out;
    out.len -= 1;
    return out;
}

// Process one sampled row, failing on blank lines, too-few fields, or jaggedness.
fn processLine(line: []const u8, delimiter: u8, expected_fields: *?usize, rows: *usize) bool {
    if (line.len == 0) return false;

    const fields = countFields(line, delimiter);
    if (fields < 2) return false;

    if (expected_fields.*) |expected| {
        if (fields != expected) return false;
    } else {
        expected_fields.* = fields;
    }
    rows.* += 1;
    return true;
}

// Return true when a score is better than the current best.
fn better(a: Score, b: Score) bool {
    if (a.rows != b.rows) return a.rows > b.rows;
    if (a.fields != b.fields) return a.fields > b.fields;
    return indexOfDelimiter(a.delimiter) < indexOfDelimiter(b.delimiter);
}

// Return the default priority index of a delimiter.
fn indexOfDelimiter(delimiter: u8) usize {
    for (default_delimiters, 0..) |candidate, ii| {
        if (candidate == delimiter) return ii;
    }
    return default_delimiters.len;
}

// Count fields in one line, ignoring delimiters inside double quotes.
fn countFields(line: []const u8, delimiter: u8) usize {
    var fields: usize = 1;
    var in_quotes = false;
    var ii: usize = 0;
    while (ii < line.len) : (ii += 1) {
        const ch = line[ii];
        if (ch == '"') {
            // Inside a quoted field, doubled quotes are an escaped literal quote.
            if (in_quotes and ii + 1 < line.len and line[ii + 1] == '"') {
                ii += 1;
                continue;
            }
            in_quotes = !in_quotes;
            continue;
        }
        if (!in_quotes and ch == delimiter) fields += 1;
    }
    return fields;
}

test "sniff success cases" {
    const cases = [_]struct {
        sample: []const u8,
        delimiter: u8,
        fields: usize = 3,
        rows: usize = 3,
    }{
        .{ .sample = "a,b,c\n1,2,3\n4,5,6\n7,8", .delimiter = ',' },
        .{ .sample = "a;b;c\n1;2;3\n4;5;6\n7;8", .delimiter = ';' },
        .{ .sample = "a\tb\tc\n1\t2\t3\n4\t5\t6\n7\t8", .delimiter = '\t' },
        .{ .sample = "a|b|c\n1|2|3\n4|5|6\n7|8", .delimiter = '|' },
        .{ .sample = "a,b,c\n\"x,y\",2,3\n\"p,q\",5,6\n\"tail", .delimiter = ',' },
        .{ .sample = "a,b,c\r\n1,2,3\r\n4,5,6\r\n7,8", .delimiter = ',' },
    };

    for (cases) |tc| {
        const got = sniff(tc.sample).?;
        try std.testing.expectEqual(tc.delimiter, got.delimiter);
        try std.testing.expectEqual(tc.fields, got.fields);
        try std.testing.expectEqual(tc.rows, got.rows);
    }
}

test "sniff null cases" {
    const cases = [_][]const u8{
        "a;b\n\n1;2\n",
        "a,b\n1,2\n",
        "hello\nworld\n",
        "a,b,c\n1,2\n",
    };

    for (cases) |sample| {
        try std.testing.expectEqual(@as(?Result, null), sniff(sample));
    }
}

test "sniff uses delimiter priority to break ties" {
    const sample =
        "a;b|c\n" ++
        "1;2|3\n" ++
        "4;5|6\n";
    const got = sniff(sample).?;
    try std.testing.expectEqual(@as(u8, ';'), got.delimiter);
}

test "sniff rejects jagged rows" {
    try std.testing.expectEqual(@as(?Result, null), sniff("a,b,c\n1,2\n"));
}

const std = @import("std");
