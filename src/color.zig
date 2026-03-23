//
// simple rgb color struct
//

// Small RGB color value with a few formatting helpers.
pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,

    // Parse a six-digit RGB hex string.
    pub fn initHex(hex: []const u8) !Color {
        const rgb = if (hex.len > 0 and hex[0] == '#') hex[1..] else hex;
        if (rgb.len % 3 != 0) return error.InvalidHex;
        const n = rgb.len / 3;
        return .{
            .r = try parseHex(rgb[0 * n .. 1 * n]),
            .g = try parseHex(rgb[1 * n .. 2 * n]),
            .b = try parseHex(rgb[2 * n .. 3 * n]),
        };
    }

    // Format this color as a six-digit lowercase hex string.
    pub fn toHex(self: Color, alloc: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(alloc, "#{x:0>2}{x:0>2}{x:0>2}", .{ self.r, self.g, self.b });
    }

    // sRGB to Y (relative luminance)
    // Return the relative luminance used for dark/light checks.
    pub fn luma(self: Color) f64 {
        const coeff = [3]f64{ 0.2126, 0.7152, 0.0722 };
        const rgb = [3]f64{
            @as(f64, @floatFromInt(self.r)) / 255.0,
            @as(f64, @floatFromInt(self.g)) / 255.0,
            @as(f64, @floatFromInt(self.b)) / 255.0,
        };
        var sum: f64 = 0;
        for (rgb, coeff) |x, c| {
            // Valgrind trips over std.math.pow(f64, x, 2.2)
            // sum += std.math.pow(f64, x, 2.2) * c;
            sum += (if (x == 0) 0 else @exp(@log(x) * 2.2)) * c;
        }
        return @round(sum * 1000.0) / 1000.0;
    }

    // Report whether the color is perceptually dark.
    pub fn isDark(self: Color) bool {
        const dark_luma = 0.36;
        return self.luma() < dark_luma;
    }

    // Report whether the color is perceptually light.
    pub fn isLight(self: Color) bool {
        return !self.isDark();
    }
};

// Parse one two-digit hex channel.
fn parseHex(hex: []const u8) !u8 {
    return switch (hex.len) {
        1 => blk: {
            const n = try std.fmt.parseInt(u8, hex, 16);
            break :blk (n << 4) | n;
        },
        2 => try std.fmt.parseInt(u8, hex, 16),
        3, 4 => try std.fmt.parseInt(u8, hex[0..2], 16),
        else => error.InvalidHex,
    };
}

//
// testing
//

test "initHex parses 6-digit channels" {
    const color = try Color.initHex("#60a5fa");
    try testing.expectEqual(0x60, color.r);
    try testing.expectEqual(0xa5, color.g);
    try testing.expectEqual(0xfa, color.b);
}

test "initHex accepts optional hash and variable widths" {
    const short = try Color.initHex("abc");
    const mid = try Color.initHex("#123456789");
    const long = try Color.initHex("111122223333");

    try testing.expectEqual(@as(u8, 0xaa), short.r);
    try testing.expectEqual(@as(u8, 0xbb), short.g);
    try testing.expectEqual(@as(u8, 0xcc), short.b);

    try testing.expectEqual(@as(u8, 0x12), mid.r);
    try testing.expectEqual(@as(u8, 0x45), mid.g);
    try testing.expectEqual(@as(u8, 0x78), mid.b);

    try testing.expectEqual(@as(u8, 0x11), long.r);
    try testing.expectEqual(@as(u8, 0x22), long.g);
    try testing.expectEqual(@as(u8, 0x33), long.b);
}

test "toHex renders hex string" {
    const hex = try (Color{ .r = 0x60, .g = 0xa5, .b = 0xfa }).toHex(testing.allocator);
    defer testing.allocator.free(hex);
    try testing.expectEqualStrings("#60a5fa", hex);
}

test "color works at comptime" {
    const color = comptime try Color.initHex("#60a5fa");

    try testing.expectEqual(@as(u8, 0x60), color.r);
    try testing.expect(color.isLight());
    try testing.expectApproxEqAbs(@as(f64, 0.368), color.luma(), 0.0001);
}

test "luma dark and light helpers" {
    const black: Color = .{ .r = 0, .g = 0, .b = 0 };
    const white: Color = .{ .r = 255, .g = 255, .b = 255 };

    try testing.expectApproxEqAbs(@as(f64, 0.0), black.luma(), 0.0001);
    try testing.expectApproxEqAbs(@as(f64, 1.0), white.luma(), 0.0001);
    try testing.expect(black.isDark());
    try testing.expect(!black.isLight());
    try testing.expect(white.isLight());
    try testing.expect(!white.isDark());
}

const std = @import("std");
const testing = std.testing;
