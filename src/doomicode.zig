//
// Lightweight best-effort Unicode-width heuristics for terminal tables.
//
// This is intentionally not a full Unicode grapheme-width implementation. It
// only tries to handle the common cases that show up in CLI output: combining
// marks, variation selectors, joined emoji, skin-tone modifiers, flag pairs,
// and a broad set of common emoji/pictographs.
//
// The goal is to keep the implementation small, fast, and good enough for
// typical terminal text, especially when compared to naive byte/codepoint
// counting. It will still be incomplete for some scripts and edge cases.
//

// Return an approximate display width for a UTF-8 string.
pub fn displayWidth(s: []const u8) usize {
    // early exit
    if (isAscii(s)) return s.len;

    var it = std.unicode.Utf8View.init(s) catch return s.len;
    var iter = it.iterator();
    var width: usize = 0;
    var state: WidthState = .{};
    while (iter.nextCodepointSlice()) |cp_slice| {
        const cp = std.unicode.utf8Decode(cp_slice) catch unreachable;
        width += codepointWidth(cp, &state);
    }
    return width;
}

// Write text truncated to approximate display width using an ellipsis.
pub fn truncate(writer: *std.Io.Writer, text: []const u8, stop: usize) !void {
    if (stop == 0) return;

    // Width can never exceed byte length, so this is a cheap universal fast path.
    if (text.len <= stop) {
        try writer.writeAll(text);
        return;
    }

    // ascii is quick
    if (isAscii(text)) {
        try truncateBytes(writer, text, stop);
        return;
    }

    var it = std.unicode.Utf8View.init(text) catch {
        try truncateBytes(writer, text, stop);
        return;
    };
    var iter = it.iterator();

    var used: usize = 0;
    var state: WidthState = .{};
    while (iter.nextCodepointSlice()) |cp_slice| {
        // Keep truncation aligned with displayWidth() by using the same heuristic.
        const cp = std.unicode.utf8Decode(cp_slice) catch unreachable;
        const w = codepointWidth(cp, &state);
        if (used + w >= stop) break;
        try writer.writeAll(cp_slice);
        used += w;
    }
    if (iter.i >= text.len) return;
    try writer.writeAll("…");
}

// Track simple state for flag pairs and joined emoji.
const WidthState = struct {
    pending_flag: bool = false,
    join_next_emoji: bool = false,
};

//
// helpers
//

// Return an approximate terminal width for one codepoint.
fn codepointWidth(cp: u21, state: *WidthState) usize {
    // Joiners glue adjacent emoji into one visual cluster.
    if (cp == 0x200D) {
        state.join_next_emoji = true;
        return 0;
    }
    // These codepoints modify the previous glyph without adding width.
    if (isCombining(cp) or isVariationSelector(cp) or isSkinToneModifier(cp)) return 0;
    // Count a regional-indicator pair as one flag of width 2.
    if (isRegionalIndicator(cp)) {
        state.join_next_emoji = false;
        if (state.pending_flag) {
            state.pending_flag = false;
            return 0;
        }
        state.pending_flag = true;
        return 2;
    }
    state.pending_flag = false;
    if (isWideEmoji(cp)) {
        // An emoji immediately after ZWJ stays in the existing cluster.
        if (state.join_next_emoji) {
            state.join_next_emoji = false;
            return 0;
        }
        return 2;
    }
    state.join_next_emoji = false;
    return 1;
}

// Return true when the whole slice is ASCII.
fn isAscii(text: []const u8) bool {
    for (text) |c| {
        if (c > 0x7f) return false;
    }
    return true;
}

// Return true for common combining-mark ranges.
fn isCombining(cp: u21) bool {
    return (cp >= 0x0300 and cp <= 0x036F) or
        (cp >= 0x1AB0 and cp <= 0x1AFF) or
        (cp >= 0x1DC0 and cp <= 0x1DFF) or
        (cp >= 0x20D0 and cp <= 0x20FF) or
        (cp >= 0xFE20 and cp <= 0xFE2F);
}

// Return true for Unicode variation selector codepoints.
fn isVariationSelector(cp: u21) bool {
    return (cp >= 0xFE00 and cp <= 0xFE0F) or (cp >= 0xE0100 and cp <= 0xE01EF);
}

// Return true for Fitzpatrick skin-tone modifier codepoints.
fn isSkinToneModifier(cp: u21) bool {
    return cp >= 0x1F3FB and cp <= 0x1F3FF;
}

// Return true for regional-indicator letters used in flags.
fn isRegionalIndicator(cp: u21) bool {
    return cp >= 0x1F1E6 and cp <= 0x1F1FF;
}

// Return true for the common emoji/pictograph blocks we treat as wide.
fn isWideEmoji(cp: u21) bool {
    return (cp >= 0x2600 and cp <= 0x27BF) or
        (cp >= 0x1F300 and cp <= 0x1FAFF);
}

// Fallback to byte-oriented truncation for invalid UTF-8 input.
fn truncateBytes(writer: *std.Io.Writer, text: []const u8, stop: usize) !void {
    if (stop == 0) return;
    if (text.len <= stop) {
        try writer.writeAll(text);
        return;
    }
    try writer.writeAll(text[0 .. stop - 1]);
    try writer.writeAll("…");
}

//
// tests
//

test "displayWidth" {
    try std.testing.expectEqual(@as(usize, 3), displayWidth("abc"));
    try std.testing.expectEqual(@as(usize, 2), displayWidth("éé"));
    try std.testing.expectEqual(@as(usize, 1), displayWidth("—"));
    try std.testing.expectEqual(@as(usize, 4), displayWidth("cafe\u{0301}"));
    try std.testing.expectEqual(@as(usize, 5), displayWidth("ok ✅"));
    try std.testing.expectEqual(@as(usize, 5), displayWidth("go 🇺🇸"));
    try std.testing.expectEqual(@as(usize, 9), displayWidth("family 👨‍👩‍👧‍👦"));
    try std.testing.expectEqual(@as(usize, 2), displayWidth(&[_]u8{ 0xff, 0x61 }));
}

test "truncate" {
    var buf: [256]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);

    try truncate(&writer, "this is too long", 8);
    try std.testing.expectEqualStrings("this is…", writer.buffered());
    writer.end = 0;

    try truncate(&writer, "cafe\u{0301} noir", 6);
    try std.testing.expectEqualStrings("cafe\u{0301} …", writer.buffered());
    writer.end = 0;

    try truncate(&writer, "ok ✅ yes", 6);
    try std.testing.expectEqualStrings("ok ✅…", writer.buffered());
    writer.end = 0;

    try truncate(&writer, "go 🇺🇸 now", 6);
    try std.testing.expectEqualStrings("go 🇺🇸…", writer.buffered());
    writer.end = 0;

    try truncate(&writer, "family 👨‍👩‍👧‍👦 test", 10);
    try std.testing.expectEqualStrings("family 👨‍👩‍👧‍👦…", writer.buffered());
    writer.end = 0;

    try truncate(&writer, "abcdef", 0);
    try std.testing.expectEqualStrings("", writer.buffered());
}

const std = @import("std");
