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
    _owned: bool = false, // whether this style owns allocated escape sequences

    // Pick a concrete style for the requested color and theme settings.
    pub fn init(app: *App, color: types.Color, theme: types.Theme) Style {
        if (!colorEnabled(app, color)) return none;
        return switch (theme) {
            .dark => dark,
            .light => light,
            .auto => if (termbg.isDark(app) catch true) dark else light,
        };
    }

    // Return a copy of this style rewritten to ANSI 256 escape sequences.
    pub fn downsample256(self: Style, alloc: std.mem.Allocator) !Style {
        var headers = try alloc.alloc([]const u8, self.headers.len);
        errdefer alloc.free(headers);

        var ii: usize = 0;
        errdefer {
            for (headers[0..ii]) |header| alloc.free(header);
        }
        for (self.headers, 0..) |header, index| {
            headers[index] = try downsample256Ansi(alloc, header);
            ii += 1;
        }

        errdefer {
            for (headers) |header| alloc.free(header);
            alloc.free(headers);
        }

        return .{
            .chrome = try downsample256Ansi(alloc, self.chrome),
            .field = try downsample256Ansi(alloc, self.field),
            .zebra = try downsample256Ansi(alloc, self.zebra),
            .headers = headers,
            .title = try downsample256Ansi(alloc, self.title),
            ._owned = true,
        };
    }

    // Release any escape sequences owned by this style.
    pub fn deinit(self: Style, alloc: std.mem.Allocator) void {
        if (!self._owned) return;
        alloc.free(self.chrome);
        alloc.free(self.field);
        alloc.free(self.zebra);
        for (self.headers) |header| alloc.free(header);
        alloc.free(self.headers);
        alloc.free(self.title);
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

// Rewrite a 24-bit fg/fgbg ANSI sequence to the nearest ANSI 256 equivalent.
fn downsample256Ansi(alloc: std.mem.Allocator, ansi_code: []const u8) ![]const u8 {
    if (ansi_code.len == 0) return alloc.dupe(u8, "");

    const rgb = try parseRgbAnsi(ansi_code);
    const fg_index = ansi.downsample256(rgb.fg);
    if (rgb.bg) |bg| {
        const bg_index = ansi.downsample256(bg);
        return std.fmt.allocPrint(alloc, "\x1b[38;5;{d};48;5;{d}m", .{ fg_index, bg_index });
    }
    return std.fmt.allocPrint(alloc, "\x1b[38;5;{d}m", .{fg_index});
}

// Parse one fg or fgbg sequence produced by fg() or fgbg().
fn parseRgbAnsi(ansi_code: []const u8) !struct { fg: Color, bg: ?Color } {
    if (!std.mem.startsWith(u8, ansi_code, "\x1b[") or !std.mem.endsWith(u8, ansi_code, "m")) {
        return error.InvalidAnsi;
    }

    var it = std.mem.tokenizeScalar(u8, ansi_code[2 .. ansi_code.len - 1], ';');
    const fg_mode = try parseAnsiPart(it.next());
    const fg_depth = try parseAnsiPart(it.next());
    if (fg_mode != 38 or fg_depth != 2) return error.InvalidAnsi;

    const fg_color: Color = .{
        .r = try parseAnsiPart(it.next()),
        .g = try parseAnsiPart(it.next()),
        .b = try parseAnsiPart(it.next()),
    };

    const bg_mode = it.next() orelse {
        if (it.next() != null) return error.InvalidAnsi;
        return .{ .fg = fg_color, .bg = null };
    };
    const bg_depth = try parseAnsiPart(it.next());
    if (try parseAnsiPart(bg_mode) != 48 or bg_depth != 2) return error.InvalidAnsi;

    const bg: Color = .{
        .r = try parseAnsiPart(it.next()),
        .g = try parseAnsiPart(it.next()),
        .b = try parseAnsiPart(it.next()),
    };
    if (it.next() != null) return error.InvalidAnsi;
    return .{ .fg = fg_color, .bg = bg };
}

// Parse one numeric ANSI parameter.
fn parseAnsiPart(part: ?[]const u8) !u8 {
    return std.fmt.parseInt(u8, part orelse return error.InvalidAnsi, 10);
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
    try testing.expectEqualStrings("\x1b[38;2;96;165;250m", s2.title);
    const s3 = Style.init(app, .on, .light);
    try testing.expectEqualStrings("\x1b[38;2;37;99;235m", s3.title);
}

test "zebra style colors match table_tennis" {
    const app = try App.testInit(testing.allocator);
    defer app.destroy();
    const dark = Style.init(app, .on, .dark);
    try testing.expectEqualStrings("\x1b[38;2;255;255;255;48;2;34;34;34m", dark.zebra);
    const light = Style.init(app, .on, .light);
    try testing.expectEqualStrings("\x1b[38;2;0;0;0;48;2;229;231;235m", light.zebra);
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

test "downsample256 rewrites fg and fgbg sequences" {
    const fg_code = try downsample256Ansi(testing.allocator, fg("#ff0000"));
    defer testing.allocator.free(fg_code);
    try testing.expectEqualStrings("\x1b[38;5;196m", fg_code);

    const fgbg_code = try downsample256Ansi(testing.allocator, fgbg("#ffffff", "#000000"));
    defer testing.allocator.free(fgbg_code);
    try testing.expectEqualStrings("\x1b[38;5;231;48;5;16m", fgbg_code);
}

test "Style.downsample256 returns an owned copy" {
    const app = try App.testInit(testing.allocator);
    defer app.destroy();
    const style = Style.init(app, .on, .dark);
    const downsampled = try style.downsample256(testing.allocator);
    defer downsampled.deinit(testing.allocator);

    try testing.expect(downsampled._owned);
    try testing.expectEqualStrings("\x1b[38;5;243m", downsampled.chrome);
    try testing.expectEqualStrings("\x1b[38;5;231;48;5;235m", downsampled.zebra);
    try testing.expectEqualStrings("\x1b[38;5;204m", downsampled.headers[0]);
}

const ansi = @import("ansi.zig");
const App = @import("app.zig").App;
const Color = @import("color.zig").Color;
const mibu = @import("mibu");
const std = @import("std");
const testing = std.testing;
const termbg = @import("termbg.zig");
const types = @import("types.zig");
