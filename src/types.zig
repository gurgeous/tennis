// Shared enums and config types used across the app.
// User-facing configuration resolved from CLI arguments.
pub const Config = struct {
    border: @import("border.zig").BorderName = .rounded,
    color: Color = .on,
    delimiter: u8 = ',',
    digits: usize = 3,
    head: usize = 0,
    row_numbers: bool = false,
    sort: []const u8 = "",
    tail: usize = 0,
    theme: Theme = .auto,
    title: []const u8 = "",
    vanilla: bool = false,
    width: usize = 0,
};

// Rows/Row/Field plus a simple two-field entry pair.
pub const Field = []const u8;
pub const Row = []const Field;
pub const Rows = []const Row;
pub const Entry = [2]Field;

// simple enums for Config
pub const Color = enum { auto, off, on };
pub const Theme = enum { auto, dark, light };
