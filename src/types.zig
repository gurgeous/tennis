// table config, from cli args
pub const Config = struct {
    color: Color = .always,
    row_numbers: bool = false,
    theme: Theme = .auto,
    title: []const u8 = "",
    width: usize = 0,
};

// simple enums for Config
pub const Color = enum { auto, always, never };
pub const Theme = enum { auto, dark, light };
