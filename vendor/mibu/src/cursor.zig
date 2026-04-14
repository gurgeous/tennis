const std = @import("std");
const fmt = std.fmt;

const lib = @import("main.zig");
const utils = lib.utils;

pub const print = struct {
    /// Moves cursor to `x` column and `y` row
    pub inline fn goTo(x: anytype, y: anytype) []const u8 {
        // i guess is ok with this size for now
        var buf: [30]u8 = undefined;
        return fmt.bufPrint(&buf, "\x1b[{d};{d}H", .{ y, x }) catch unreachable;
    }

    /// Moves cursor up `y` rows
    pub inline fn goUp(y: anytype) []const u8 {
        // i guess is ok with this size for now
        var buf: [30]u8 = undefined;
        return fmt.bufPrint(&buf, "\x1b[{d}A", .{y}) catch unreachable;
    }

    /// Moves cursor down `y` rows
    pub inline fn goDown(y: anytype) []const u8 {
        // i guess is ok with this size for now
        var buf: [30]u8 = undefined;
        return fmt.bufPrint(&buf, "\x1b[{d}B", .{y}) catch unreachable;
    }

    /// Moves cursor left `x` columns
    pub inline fn goLeft(x: anytype) []const u8 {
        // i guess is ok with this size for now
        var buf: [30]u8 = undefined;
        return fmt.bufPrint(&buf, "\x1b[{d}D", .{x}) catch unreachable;
    }

    /// Moves cursor right `x` columns
    pub inline fn goRight(x: anytype) []const u8 {
        // i guess is ok with this size for now
        var buf: [30]u8 = undefined;
        return fmt.bufPrint(&buf, "\x1b[{d}C", .{x}) catch unreachable;
    }

    /// Hide the cursor
    pub inline fn hide() []const u8 {
        return utils.comptimeCsi("?25l", .{});
    }

    /// Show the cursor
    pub inline fn show() []const u8 {
        return utils.comptimeCsi("?25h", .{});
    }

    /// Save cursor position
    pub inline fn save() []const u8 {
        return utils.comptimeCsi("s", .{});
    }

    /// Restore cursor position
    pub inline fn restore() []const u8 {
        return utils.comptimeCsi("u", .{});
    }
};

/// Moves cursor to `x` column and `y` row
pub fn goTo(writer: *std.Io.Writer, x: anytype, y: anytype) !void {
    return writer.print(utils.csi ++ "{d};{d}H", .{ y, x });
}

/// Moves cursor up `y` rows
pub fn goUp(writer: *std.Io.Writer, y: anytype) !void {
    return writer.print(utils.csi ++ "{d}A", .{y});
}

/// Moves cursor down `y` rows
pub fn goDown(writer: *std.Io.Writer, y: anytype) !void {
    return writer.print(utils.csi ++ "{d}B", .{y});
}

/// Moves cursor left `x` columns
pub fn goLeft(writer: *std.Io.Writer, x: anytype) !void {
    return writer.print(utils.csi ++ "{d}D", .{x});
}

/// Moves cursor right `x` columns
pub fn goRight(writer: *std.Io.Writer, x: anytype) !void {
    return writer.print(utils.csi ++ "{d}C", .{x});
}

/// Hide the cursor
pub fn hide(writer: *std.Io.Writer) !void {
    return writer.print(utils.csi ++ "?25l", .{});
}

/// Show the cursor
pub fn show(writer: *std.Io.Writer) !void {
    return writer.print(utils.csi ++ "?25h", .{});
}

/// Save cursor position
pub fn save(writer: *std.Io.Writer) !void {
    return writer.print(utils.csi ++ "s", .{});
}

/// Restore cursor position
pub fn restore(writer: *std.Io.Writer) !void {
    return writer.print(utils.csi ++ "u", .{});
}

pub const Position = struct {
    row: usize,
    col: usize,
};

/// Returns the cursor's coordinates. The terminal needs to be
/// in raw mode or at least have echo disabled.
pub fn getPosition(in: *std.Io.Reader, out: *std.io.Writer) !Position {
    try out.print("\x1b[6n", .{});
    try out.flush();

    var buf: [6]u8 = undefined;
    const bytes = try in.readSliceShort(&buf);
    const data = buf[0..bytes];

    // example response: \x1B[12;45R
    if (data[0] != 0x1B or data[1] != '[') {
        return error.InvalidResponse;
    }

    var it = std.mem.tokenizeAny(u8, data[2..], ";R");
    const row_str = it.next() orelse return error.InvalidResponse;
    const col_str = it.next() orelse return error.InvalidResponse;

    const row = try std.fmt.parseUnsigned(usize, row_str, 10);
    const col = try std.fmt.parseUnsigned(usize, col_str, 10);
    return .{ .row = row, .col = col };
}
