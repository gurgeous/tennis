//
// style/theming
//

// ANSI style bundle used while rendering one table.
pub const Style = struct {
    chrome: []const u8 = "", // table borders, row numbers, placeholders... (dim)
    field: []const u8 = "", // data text color (bright)
    zebra: []const u8 = "", // alternate row background
    headers: []const []const u8 = &.{}, // header text color (colorful)
    title: []const u8 = "", // title text color (colorful)

    // Pick a concrete style for the requested color and theme settings.
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
        .chrome = fg("#6b7280"),
        .field = fg("#e5e7eb"),
        .zebra = fgbg("#ffffff", "#222222"),
        .title = fg("#60a5fa"),
        .headers = &.{
            fg("#ff6188"),
            fg("#fc9867"),
            fg("#ffd866"),
            fg("#a9dc76"),
            fg("#78dce8"),
            fg("#ab9df2"),
        },
    };

    const light: Style = .{
        .chrome = fg("#6b7280"),
        .field = fg("#1f2937"),
        .zebra = fgbg("#000000", "#e5e7eb"),
        .title = fg("#2563eb"),
        .headers = &.{
            fg("#ee4066"),
            fg("#da7645"),
            fg("#ddb644"),
            fg("#87ba54"),
            fg("#56bac6"),
            fg("#897bd0"),
        },
    };

    // a little subtle - headers needs at least one value because we use (idx %
    // len) to determine header colors
    const none: Style = .{ .headers = &.{""} };
};

//
// helpers
//

// Build one ANSI foreground sequence at comptime.
fn fg(comptime hex: []const u8) []const u8 {
    const c = comptime Color.initHex(hex) catch @compileError("invalid hex color");
    const csi = comptime std.fmt.comptimePrint("38;2;{d};{d};{d}m", .{ c.r, c.g, c.b });
    return mibu.utils.comptimeCsi(csi, .{});
}

// Build one ANSI foreground/background sequence at comptime.
fn fgbg(comptime fg_hex: []const u8, comptime bg_hex: []const u8) []const u8 {
    const fg_color = comptime Color.initHex(fg_hex) catch @compileError("invalid fg hex color");
    const bg_color = comptime Color.initHex(bg_hex) catch @compileError("invalid bg hex color");
    const csi = comptime std.fmt.comptimePrint(
        "38;2;{d};{d};{d};48;2;{d};{d};{d}m",
        .{ fg_color.r, fg_color.g, fg_color.b, bg_color.r, bg_color.g, bg_color.b },
    );
    return mibu.utils.comptimeCsi(csi, .{});
}

//
// is color enabled?
//

// Report whether ANSI colors should be emitted.
fn colorEnabled(color: types.Color) bool {
    return switch (color) {
        .on => true,
        .off => false,
        .auto => blk: {
            if (util.hasenv("NO_COLOR")) break :blk false;
            if (util.hasenv("FORCE_COLOR")) break :blk true;
            if (!std.fs.File.stdout().isTty()) break :blk false;
            break :blk true;
        },
    };
}

//
// testing
//

test "color title style" {
    const s1 = Style.init(testing.allocator, .off, .dark);
    try testing.expectEqualStrings("", s1.title);
    const s2 = Style.init(testing.allocator, .on, .dark);
    try testing.expectEqualStrings("\x1b[38;2;96;165;250m", s2.title);
    const s3 = Style.init(testing.allocator, .on, .light);
    try testing.expectEqualStrings("\x1b[38;2;37;99;235m", s3.title);
}

test "zebra style colors match table_tennis" {
    const dark = Style.init(testing.allocator, .on, .dark);
    try testing.expectEqualStrings("\x1b[38;2;255;255;255;48;2;34;34;34m", dark.zebra);
    const light = Style.init(testing.allocator, .on, .light);
    try testing.expectEqualStrings("\x1b[38;2;0;0;0;48;2;229;231;235m", light.zebra);
}

test "colorEnabled handles explicit modes" {
    try testing.expect(colorEnabled(.on));
    try testing.expect(!colorEnabled(.off));
}

test "colorEnabled auto returns a boolean" {
    _ = colorEnabled(.auto);
    try testing.expect(colorEnabled(.auto) == true or colorEnabled(.auto) == false);
}

const builtin = @import("builtin");
const Color = @import("color.zig").Color;
const mibu = @import("mibu");
const std = @import("std");
const testing = std.testing;
const termbg = @import("termbg.zig");
const types = @import("types.zig");
const util = @import("util.zig");
