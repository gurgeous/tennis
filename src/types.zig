// table config, from cli args
pub const Config = struct {
    color: Color = .on,
    delimiter: u8 = ',',
    digits: usize = 3,
    row_numbers: bool = false,
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
