const std = @import("std");

pub const clear = @import("clear.zig");
pub const color = @import("color.zig");
pub const cursor = @import("cursor.zig");
pub const style = @import("style.zig");
pub const utils = @import("utils.zig");
pub const term = @import("term.zig");
pub const events = @import("event.zig");
pub const scroll = @import("scroll.zig");

pub const enableWindowsVTS = switch (@import("builtin").os.tag) {
    .windows => @import("utils.zig").enableWindowsVTS,
    else => @compileError("enableWindowsVTS is supported only on Windows"),
};

test {
    _ = clear;
    _ = color;
    _ = cursor;
    _ = style;
    _ = utils;
    _ = term;
    _ = events;
    _ = scroll;
}
