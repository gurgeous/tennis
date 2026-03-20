// table config, from cli args
pub const Config = struct {
    border: @import("border.zig").BorderName = .rounded,
    color: Color = .on,
    delimiter: u8 = ',',
    digits: usize = 3,
    head: usize = 0,
    row_numbers: bool = false,
    tail: usize = 0,
    theme: Theme = .auto,
    title: []const u8 = "",
    vanilla: bool = false,
    width: usize = 0,
};

// raw data types
pub const Field = []const u8;
pub const Row = []const Field;
pub const Rows = []const Row;

// simple enums for Config
pub const Color = enum { auto, off, on };
pub const Theme = enum { auto, dark, light };
