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
    pub fn init(app: *App, color: types.Color, theme: types.Theme) Style {
        if (!colorEnabled(app, color)) return none;
        return switch (theme) {
            .dark => dark,
            .light => light,
            .auto => if (termbg.isDark(app) catch true) dark else light,
        };
    }

    //
    // the actual colors
    //

    const dark: Style = .{
        .chrome = fg(243), // Grey46
        .field = fg(254), // Grey89
        .zebra = fgbg(231, 235), // White on Grey15
        .title = fg(75), // SteelBlue1
        .headers = &.{
            fg(204), // IndianRed1_2
            fg(209), // Salmon1
            fg(221), // LightGoldenrod2_2
            fg(150), // DarkSeaGreen3_2
            fg(116), // DarkSlateGray3
            fg(147), // LightSteelBlue
        },
    };

    const light: Style = .{
        .chrome = fg(243), // Grey46
        .field = fg(235), // Grey15
        .zebra = fgbg(16, 254), // Black on Grey89
        .title = fg(26), // DodgerBlue3
        .headers = &.{
            fg(203), // IndianRed1
            fg(173), // LightSalmon3
            fg(179), // LightGoldenrod3
            fg(107), // DarkOliveGreen3
            fg(74), // SkyBlue3
            fg(104), // MediumPurple
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
fn fg(comptime index: u8) []const u8 {
    const csi = comptime std.fmt.comptimePrint("38;5;{d}m", .{index});
    return mibu.utils.comptimeCsi(csi, .{});
}

// Build one ANSI foreground/background sequence at comptime.
fn fgbg(comptime fg_index: u8, comptime bg_index: u8) []const u8 {
    const csi = comptime std.fmt.comptimePrint("38;5;{d};48;5;{d}m", .{ fg_index, bg_index });
    return mibu.utils.comptimeCsi(csi, .{});
}

//
// is color enabled?
//

// Report whether ANSI colors should be emitted.
fn colorEnabled(app: *const App, color: types.Color) bool {
    return switch (color) {
        .on => true,
        .off => false,
        .auto => blk: {
            if (app.env.NO_COLOR) break :blk false;
            if (app.env.FORCE_COLOR) break :blk true;
            if (!(std.Io.File.stdout().isTty(app.io) catch false)) break :blk false;
            break :blk true;
        },
    };
}

//
// testing
//

test "color title style" {
    const app = try App.testInit(testing.allocator);
    defer app.destroy();
    const s1 = Style.init(app, .off, .dark);
    try testing.expectEqualStrings("", s1.title);
    const s2 = Style.init(app, .on, .dark);
    try testing.expectEqualStrings("\x1b[38;5;75m", s2.title);
    const s3 = Style.init(app, .on, .light);
    try testing.expectEqualStrings("\x1b[38;5;26m", s3.title);
}

test "zebra style colors match table_tennis" {
    const app = try App.testInit(testing.allocator);
    defer app.destroy();
    const dark = Style.init(app, .on, .dark);
    try testing.expectEqualStrings("\x1b[38;5;231;48;5;235m", dark.zebra);
    const light = Style.init(app, .on, .light);
    try testing.expectEqualStrings("\x1b[38;5;16;48;5;254m", light.zebra);
}

test "colorEnabled handles explicit modes" {
    const app = try App.testInit(testing.allocator);
    defer app.destroy();
    try testing.expect(colorEnabled(app, .on));
    try testing.expect(!colorEnabled(app, .off));
}

test "colorEnabled auto returns a boolean" {
    const app = try App.testInit(testing.allocator);
    defer app.destroy();
    _ = colorEnabled(app, .auto);
    try testing.expect(colorEnabled(app, .auto) == true or colorEnabled(app, .auto) == false);
}

const App = @import("app.zig").App;
const mibu = @import("mibu");
const std = @import("std");
const testing = std.testing;
const termbg = @import("termbg.zig");
const types = @import("types.zig");
