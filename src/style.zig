//
// style/theming
//

pub const Style = struct {
    chrome: []const u8 = "", // table borders, row numbers, placeholders... (dim)
    field: []const u8 = "", // data text color (bright)
    headers: []const []const u8 = &.{}, // header text color (colorful)
    title: []const u8 = "", // title text color (colorful)

    pub fn init(alloc: std.mem.Allocator, color: types.Color, theme: types.Theme) Style {
        if (!colorEnabled(color)) return none;
        return switch (theme) {
            .dark => dark,
            .light => light,
            .auto => if (termbg.isDark(alloc) catch true) dark else light,
        };
    }

    //
    // the actual colors
    //

    const dark: Style = .{
        .chrome = fg("#6b7280", false),
        .field = fg("#e5e7eb", false),
        .title = fg("#60a5fa", true),
        .headers = &.{
            fg("#ff6188", true),
            fg("#fc9867", true),
            fg("#ffd866", true),
            fg("#a9dc76", true),
            fg("#78dce8", true),
            fg("#ab9df2", true),
        },
    };

    const light: Style = .{
        .chrome = fg("#6b7280", false),
        .field = fg("#1f2937", false),
        .title = fg("#2563eb", true),
        .headers = &.{
            fg("#ee4066", true),
            fg("#da7645", true),
            fg("#ddb644", true),
            fg("#87ba54", true),
            fg("#56bac6", true),
            fg("#897bd0", true),
        },
    };

    // a little subtle - headers needs at least one value because we use (idx %
    // len) to determine header colors
    const none: Style = .{ .headers = &.{""} };
};

//
// helpers
//

fn fg(comptime hex: []const u8, comptime is_bold: bool) []const u8 {
    const c = comptime Color.initHex(hex) catch @compileError("invalid hex color");
    const bold_prefix = if (is_bold) "1;" else "";
    const csi = comptime std.fmt.comptimePrint("{s}38;2;{d};{d};{d}m", .{ bold_prefix, c.r, c.g, c.b });
    return mibu.utils.comptimeCsi(csi, .{});
}

//
// is color enabled?
//

fn colorEnabled(color: types.Color) bool {
    return switch (color) {
        .on => true,
        .off => false,
        .auto => blk: {
            if (util.hasenv("NO_COLOR")) break :blk false;
            if (util.hasenv("FORCE_COLOR")) break :blk true;
            if (!std.posix.isatty(std.fs.File.stdout().handle)) break :blk false;
            break :blk true;
        },
    };
}

//
// tests
//

test "color title style" {
    const s1 = Style.init(std.testing.allocator, .off, .dark);
    try std.testing.expectEqualStrings("", s1.title);
    const s2 = Style.init(std.testing.allocator, .on, .dark);
    try std.testing.expectEqualStrings("\x1b[1;38;2;96;165;250m", s2.title);
    const s3 = Style.init(std.testing.allocator, .on, .light);
    try std.testing.expectEqualStrings("\x1b[1;38;2;37;99;235m", s3.title);
}

test "colorEnabled handles explicit modes" {
    try std.testing.expect(colorEnabled(.on));
    try std.testing.expect(!colorEnabled(.off));
}

test "colorEnabled auto returns a boolean" {
    _ = colorEnabled(.auto);
    try std.testing.expect(colorEnabled(.auto) == true or colorEnabled(.auto) == false);
}

const Color = @import("color.zig").Color;
const mibu = @import("mibu");
const std = @import("std");
const termbg = @import("termbg.zig");
const types = @import("types.zig");
const util = @import("util.zig");
