//!  Clear screen.
//! Note: Clear doesn't move the cursor, so the cursor will stay at the same position,
//! to move cursor check `Cursor`.

const std = @import("std");

const lib = @import("main.zig");
const utils = lib.utils;

pub const print = struct {
    /// Clear from cursor until end of screen
    pub const screen_from_cursor = utils.comptimeCsi("0J", .{});

    /// Clear from cursor to beginning of screen
    pub const screen_to_cursor = utils.comptimeCsi("1J", .{});

    /// Clear all screen
    pub const all = utils.comptimeCsi("2J", .{});

    /// Clear from cursor to end of line
    pub const line_from_cursor = utils.comptimeCsi("0K", .{});

    /// Clear start of line to the cursor
    pub const line_to_cursor = utils.comptimeCsi("1K", .{});

    /// Clear entire line
    pub const line = utils.comptimeCsi("2K", .{});
};

/// Clear from cursor until end of screen
pub fn screenFromCursor(writer: *std.Io.Writer) !void {
    return writer.print(utils.csi ++ utils.clear_screen_from_cursor, .{});
}

/// Clear from cursor to beginning of screen
pub fn screenToCursor(writer: *std.Io.Writer) !void {
    return writer.print(utils.csi ++ utils.clear_screen_to_cursor, .{});
}

/// Clear all screen
pub fn all(writer: *std.Io.Writer) !void {
    return writer.print(utils.csi ++ utils.clear_all, .{});
}

/// Clear from cursor to end of line
pub fn lineFromCursor(writer: *std.Io.Writer) !void {
    return writer.print(utils.csi ++ utils.clear_line_from_cursor, .{});
}

/// Clear start of line to the cursor
pub fn lineToCursor(writer: *std.Io.Writer) !void {
    return writer.print(utils.csi ++ utils.clear_line_to_cursor, .{});
}

/// Clear entire line
pub fn entireLine(writer: *std.Io.Writer) !void {
    return writer.print(utils.csi ++ utils.clear_line, .{});
}
