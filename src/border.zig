// Prototype border model.
//
// The specimen constants below are adapted from Nushell table themes, which in
// turn are built on the `tabled` crate's style system. This file is only an
// experiment: it does not plug into render.zig yet.
//
// Unsupported on purpose:
// - with_love
// - default as a separate name, since Nushell's current default is the same as rounded
//
// Each specimen is a tiny canonical table with 3 columns and 2 rows. The
// cells are width-1 (`A`..`I`) so the parser can infer separators directly
// from the visible border sample instead of from a hand-built struct.

const specimens = struct {
    // Canonical border samples adapted from Nushell/tabled themes.
    const ascii_rounded =
        \\.-----.
        \\|A|B|C|
        \\|D|E|F|
        \\|G|H|I|
        \\'-----'
    ;
    const basic =
        \\+-+-+-+
        \\|A|B|C|
        \\+-+-+-+
        \\|D|E|F|
        \\+-+-+-+
        \\|G|H|I|
        \\+-+-+-+
    ;
    const basic_compact =
        \\+-+-+-+
        \\|A|B|C|
        \\|D|E|F|
        \\|G|H|I|
        \\+-+-+-+
    ;
    const compact =
        \\─┬─┬─
        \\A│B│C
        \\─┼─┼─
        \\D│E│F
        \\G│H│I
        \\─┴─┴─
    ;
    const compact_double =
        \\═╦═╦═
        \\A║B║C
        \\═╬═╬═
        \\D║E║F
        \\G║H║I
        \\═╩═╩═
    ;
    const dots =
        \\.......
        \\:A:B:C:
        \\:D:E:F:
        \\:G:H:I:
        \\:.:.:.:
    ;
    const double =
        \\╔═╦═╦═╗
        \\║A║B║C║
        \\╠═╬═╬═╣
        \\║D║E║F║
        \\║G║H║I║
        \\╚═╩═╩═╝
    ;
    const heavy =
        \\┏━┳━┳━┓
        \\┃A┃B┃C┃
        \\┣━╋━╋━┫
        \\┃D┃E┃F┃
        \\┃G┃H┃I┃
        \\┗━┻━┻━┛
    ;
    const light =
        \\A B C
        \\─────
        \\D E F
        \\G H I
    ;
    const markdown =
        \\|A|B|C|
        \\|-|-|-|
        \\|D|E|F|
        \\|G|H|I|
    ;
    const none =
        \\A B C
        \\D E F
        \\G H I
    ;
    const psql =
        \\A|B|C
        \\-+-+-
        \\D|E|F
        \\G|H|I
    ;
    const reinforced =
        \\┏─┬─┬─┓
        \\│A│B│C│
        \\│D│E│F│
        \\│G│H│I│
        \\┗─┴─┴─┛
    ;
    const restructured =
        \\A B C
        \\= = =
        \\D E F
        \\G H I
        \\= = =
    ;
    const rounded =
        \\╭─┬─┬─╮
        \\│A│B│C│
        \\├─┼─┼─┤
        \\│D│E│F│
        \\│G│H│I│
        \\╰─┴─┴─╯
    ;
    const single =
        \\┌─┬─┬─┐
        \\│A│B│C│
        \\├─┼─┼─┤
        \\│D│E│F│
        \\│G│H│I│
        \\└─┴─┴─┘
    ;
    const thin =
        \\┌─┬─┬─┐
        \\│A│B│C│
        \\├─┼─┼─┤
        \\│D│E│F│
        \\├─┼─┼─┤
        \\│G│H│I│
        \\└─┴─┴─┘
    ;
};

// Public border names exposed through CLI/config.
pub const BorderName = enum {
    ascii_rounded,
    basic,
    basic_compact,
    compact,
    compact_double,
    dots,
    double,
    heavy,
    light,
    markdown,
    none,
    psql,
    reinforced,
    restructured,
    rounded,
    single,
    thin,
};

// Parsed horizontal separator line.
pub const BorderLine = union(enum) {
    none,
    continuous: ContinuousLine,
    segmented: SegmentedLine,
};

// Parsed border style consumed by render.
pub const BorderStyle = struct {
    top: BorderLine,
    header: BorderLine,
    row: BorderLine,
    bottom: BorderLine,
    left: []const u8,
    mid: []const u8,
    right: []const u8,
};

pub fn getBorder(border: BorderName) BorderStyle {
    return parseSpecimen(specimen(border));
}

fn specimen(border: BorderName) []const u8 {
    return switch (border) {
        .ascii_rounded => specimens.ascii_rounded,
        .basic => specimens.basic,
        .basic_compact => specimens.basic_compact,
        .compact => specimens.compact,
        .compact_double => specimens.compact_double,
        .dots => specimens.dots,
        .double => specimens.double,
        .heavy => specimens.heavy,
        .light => specimens.light,
        .markdown => specimens.markdown,
        .none => specimens.none,
        .psql => specimens.psql,
        .reinforced => specimens.reinforced,
        .restructured => specimens.restructured,
        .rounded => specimens.rounded,
        .single => specimens.single,
        .thin => specimens.thin,
    };
}

fn parseSpecimen(input: []const u8) BorderStyle {
    const lines = splitLines(input);
    const header_index = findLine(lines, "A", "B", "C");
    const first_row_index = findLine(lines, "D", "E", "F");
    const second_row_index = findLine(lines, "G", "H", "I");
    const row_style = parseRow(lines.items[header_index]);

    return .{
        .top = if (header_index > 0) parseRule(lines.items[0], row_style) else .none,
        .header = if (first_row_index > header_index + 1) parseRule(lines.items[header_index + 1], row_style) else .none,
        .row = if (second_row_index > first_row_index + 1) parseRule(lines.items[first_row_index + 1], row_style) else .none,
        .bottom = if (second_row_index + 1 < lines.len) parseRule(lines.items[second_row_index + 1], row_style) else .none,
        .left = row_style.left,
        .mid = row_style.mid,
        .right = row_style.right,
    };
}

fn parseRow(line: []const u8) BorderStyle {
    const a = std.mem.indexOfScalar(u8, line, 'A').?;
    const b = std.mem.indexOfScalar(u8, line, 'B').?;
    const c = std.mem.indexOfScalar(u8, line, 'C').?;
    const mid = line[a + 1 .. b];

    std.debug.assert(std.mem.eql(u8, mid, line[b + 1 .. c]));

    return .{
        .top = .none,
        .header = .none,
        .row = .none,
        .bottom = .none,
        .left = line[0..a],
        .mid = mid,
        .right = line[c + 1 ..],
    };
}

// Parse a horizontal rule by using the inferred row separators as the guide.
// If the middle slots match the fill char, this is a continuous rule like
// `─────` or `.-----.`; otherwise it is segmented like `├─┼─┼─┤`.
fn parseRule(line: []const u8, row_style: BorderStyle) BorderLine {
    const left_glyphs = glyphCount(row_style.left);
    const mid_glyphs = glyphCount(row_style.mid);
    const right_glyphs = glyphCount(row_style.right);

    var glyphs: [32]Glyph = undefined;
    const nglyphs = splitGlyphs(line, &glyphs);
    const needed = left_glyphs + right_glyphs + 3 + 2 * mid_glyphs;
    std.debug.assert(nglyphs == needed);

    const fill1 = glyphRange(line, glyphs[0..nglyphs], left_glyphs, left_glyphs + 1);
    const mid1 = glyphRange(line, glyphs[0..nglyphs], left_glyphs + 1, left_glyphs + 1 + mid_glyphs);
    const fill2 = glyphRange(line, glyphs[0..nglyphs], left_glyphs + 1 + mid_glyphs, left_glyphs + 2 + mid_glyphs);
    const mid2 = glyphRange(line, glyphs[0..nglyphs], left_glyphs + 2 + mid_glyphs, left_glyphs + 2 + 2 * mid_glyphs);
    const fill3 = glyphRange(line, glyphs[0..nglyphs], left_glyphs + 2 + 2 * mid_glyphs, left_glyphs + 3 + 2 * mid_glyphs);

    std.debug.assert(std.mem.eql(u8, fill1, fill2));
    std.debug.assert(std.mem.eql(u8, fill1, fill3));

    if (std.mem.eql(u8, fill1, mid1) and std.mem.eql(u8, fill1, mid2)) {
        return .{ .continuous = .{
            .left = glyphRange(line, glyphs[0..nglyphs], 0, left_glyphs),
            .fill = fill1,
            .right = glyphRange(line, glyphs[0..nglyphs], nglyphs - right_glyphs, nglyphs),
        } };
    }

    std.debug.assert(std.mem.eql(u8, mid1, mid2));
    return .{ .segmented = .{
        .left = glyphRange(line, glyphs[0..nglyphs], 0, left_glyphs),
        .fill = fill1,
        .mid = mid1,
        .right = glyphRange(line, glyphs[0..nglyphs], nglyphs - right_glyphs, nglyphs),
    } };
}

fn splitLines(input: []const u8) Lines {
    var out: [7][]const u8 = undefined;
    var it = std.mem.splitScalar(u8, input, '\n');
    var n: usize = 0;
    while (it.next()) |line| : (n += 1) {
        out[n] = line;
    }
    return .{ .items = out, .len = n };
}

fn findLine(lines: Lines, a: []const u8, b: []const u8, c: []const u8) usize {
    for (lines.items[0..lines.len], 0..) |line, ii| {
        if (std.mem.indexOf(u8, line, a) != null and
            std.mem.indexOf(u8, line, b) != null and
            std.mem.indexOf(u8, line, c) != null)
        {
            return ii;
        }
    }
    unreachable;
}

fn splitGlyphs(line: []const u8, out: *[32]Glyph) usize {
    var n: usize = 0;
    var i: usize = 0;
    while (i < line.len) : (n += 1) {
        const len = std.unicode.utf8ByteSequenceLength(line[i]) catch unreachable;
        out[n] = .{ .start = i, .end = i + len };
        i += len;
    }
    return n;
}

fn glyphCount(line: []const u8) usize {
    var glyphs: [32]Glyph = undefined;
    return splitGlyphs(line, &glyphs);
}

fn glyphRange(line: []const u8, glyphs: []const Glyph, start: usize, end: usize) []const u8 {
    if (start == end) return "";
    return line[glyphs[start].start..glyphs[end - 1].end];
}

fn renderRule(buf: []u8, style_: BorderStyle, line: BorderLine) []const u8 {
    var n: usize = 0;
    switch (line) {
        .none => {},
        .continuous => |rule| {
            append(buf, &n, rule.left);
            for (0..3 + 2 * glyphCount(style_.mid)) |_| append(buf, &n, rule.fill);
            append(buf, &n, rule.right);
        },
        .segmented => |rule| {
            append(buf, &n, rule.left);
            append(buf, &n, rule.fill);
            append(buf, &n, rule.mid);
            append(buf, &n, rule.fill);
            append(buf, &n, rule.mid);
            append(buf, &n, rule.fill);
            append(buf, &n, rule.right);
        },
    }
    return buf[0..n];
}

fn renderRow(buf: []u8, style_: BorderStyle, a: []const u8, b: []const u8, c: []const u8) []const u8 {
    var n: usize = 0;
    append(buf, &n, style_.left);
    append(buf, &n, a);
    append(buf, &n, style_.mid);
    append(buf, &n, b);
    append(buf, &n, style_.mid);
    append(buf, &n, c);
    append(buf, &n, style_.right);
    return buf[0..n];
}

fn append(buf: []u8, n: *usize, text: []const u8) void {
    @memcpy(buf[n.* .. n.* + text.len], text);
    n.* += text.len;
}

// Continuous horizontal rule like `────` or `.....`.
const ContinuousLine = struct {
    left: []const u8,
    fill: []const u8,
    right: []const u8,
};

// UTF-8 glyph span within a specimen line.
const Glyph = struct {
    start: usize,
    end: usize,
};

// Split specimen lines with a fixed small maximum.
const Lines = struct {
    items: [7][]const u8,
    len: usize,
};

// Segmented horizontal rule like `├─┼─┤`.
const SegmentedLine = struct {
    left: []const u8,
    fill: []const u8,
    mid: []const u8,
    right: []const u8,
};

test "all supported borders roundtrip through the specimen parser" {
    const cases = [_]BorderName{
        .ascii_rounded,
        .basic,
        .basic_compact,
        .compact,
        .compact_double,
        .dots,
        .double,
        .heavy,
        .light,
        .markdown,
        .none,
        .psql,
        .reinforced,
        .restructured,
        .rounded,
        .single,
        .thin,
    };

    for (cases) |border| {
        const want = splitLines(specimen(border));
        const got = getBorder(border);

        var bufs: [7][32]u8 = undefined;
        const lines = [_][]const u8{
            renderRule(&bufs[0], got, got.top),
            renderRow(&bufs[1], got, "A", "B", "C"),
            renderRule(&bufs[2], got, got.header),
            renderRow(&bufs[3], got, "D", "E", "F"),
            renderRule(&bufs[4], got, got.row),
            renderRow(&bufs[5], got, "G", "H", "I"),
            renderRule(&bufs[6], got, got.bottom),
        };
        const have = compactLines(lines);

        try std.testing.expectEqual(want.len, have.len);
        for (want.items[0..want.len], 0..) |line, ii| {
            try std.testing.expectEqualStrings(line, have.items[ii]);
        }
    }
}

test "thin has a row separator but rounded does not" {
    try std.testing.expect(getBorder(.thin).row != .none);
    try std.testing.expect(getBorder(.rounded).row == .none);
}

test "psql omits outer borders" {
    const psql = getBorder(.psql);
    try std.testing.expectEqualStrings("", psql.left);
    try std.testing.expectEqualStrings("", psql.right);
}

test "reinforced has a bottom border but no header separator" {
    const reinforced = getBorder(.reinforced);
    try std.testing.expect(reinforced.header == .none);
    try std.testing.expect(reinforced.bottom != .none);
}

fn compactLines(lines: [7][]const u8) Lines {
    var out: [7][]const u8 = undefined;
    var n: usize = 0;
    for (lines) |line| {
        if (line.len == 0) continue;
        out[n] = line;
        n += 1;
    }
    return .{ .items = out, .len = n };
}

const std = @import("std");
