//
// simple rgb color struct
//

pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,

    pub fn init(r: u8, g: u8, b: u8) Color {
        return .{ .r = r, .g = g, .b = b };
    }

    pub fn initHex(hex: []const u8) !Color {
        const rgb = if (hex.len > 0 and hex[0] == '#') hex[1..] else hex;
        if (rgb.len != 3 and rgb.len != 6 and rgb.len != 9 and rgb.len != 12) return error.InvalidHex;
        const n = rgb.len / 3;
        return .{
            .r = try parseHex(rgb[0 * n .. 1 * n]),
            .g = try parseHex(rgb[1 * n .. 2 * n]),
            .b = try parseHex(rgb[2 * n .. 3 * n]),
        };
    }

    pub fn toHex(self: Color, alloc: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(alloc, "#{x:0>2}{x:0>2}{x:0>2}", .{ self.r, self.g, self.b });
    }

    pub fn luma(self: Color) f64 {
        const coeff = [3]f64{ 0.2126, 0.7152, 0.0722 };
        const rgb = [3]f64{
            @as(f64, @floatFromInt(self.r)) / 255.0,
            @as(f64, @floatFromInt(self.g)) / 255.0,
            @as(f64, @floatFromInt(self.b)) / 255.0,
        };
        var sum: f64 = 0;
        for (rgb, coeff) |x, c| {
            sum += std.math.pow(f64, x, 2.2) * c;
        }
        return @round(sum * 1000.0) / 1000.0;
    }

    pub fn isDark(self: Color) bool {
        const dark_luma = 0.36;
        return self.luma() < dark_luma;
    }

    pub fn isLight(self: Color) bool {
        return !self.isDark();
    }
};

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
// tests
//

test "initHex parses 6-digit channels" {
    const color = try Color.initHex("#60a5fa");
    try std.testing.expectEqual(0x60, color.r);
    try std.testing.expectEqual(0xa5, color.g);
    try std.testing.expectEqual(0xfa, color.b);
}

test "initHex accepts optional hash and variable widths" {
    const short = try Color.initHex("abc");
    const mid = try Color.initHex("#123456789");
    const long = try Color.initHex("111122223333");

    try std.testing.expectEqual(@as(u8, 0xaa), short.r);
    try std.testing.expectEqual(@as(u8, 0xbb), short.g);
    try std.testing.expectEqual(@as(u8, 0xcc), short.b);

    try std.testing.expectEqual(@as(u8, 0x12), mid.r);
    try std.testing.expectEqual(@as(u8, 0x45), mid.g);
    try std.testing.expectEqual(@as(u8, 0x78), mid.b);

    try std.testing.expectEqual(@as(u8, 0x11), long.r);
    try std.testing.expectEqual(@as(u8, 0x22), long.g);
    try std.testing.expectEqual(@as(u8, 0x33), long.b);
}

test "toHex renders hex string" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const hex = try Color.init(0x60, 0xa5, 0xfa).toHex(arena.allocator());
    try std.testing.expectEqualStrings("#60a5fa", hex);
}

test "color works at comptime" {
    const color = comptime try Color.initHex("#60a5fa");

    try std.testing.expectEqual(@as(u8, 0x60), color.r);
    try std.testing.expect(color.isLight());
    try std.testing.expectApproxEqAbs(@as(f64, 0.368), color.luma(), 0.0001);
}

test "luma dark and light helpers" {
    const black = Color.init(0, 0, 0);
    const white = Color.init(255, 255, 255);

    try std.testing.expectApproxEqAbs(@as(f64, 0.0), black.luma(), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), white.luma(), 0.0001);
    try std.testing.expect(black.isDark());
    try std.testing.expect(!black.isLight());
    try std.testing.expect(white.isLight());
    try std.testing.expect(!white.isDark());
}

const std = @import("std");
