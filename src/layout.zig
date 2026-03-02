pub const Layout = struct {
    const min_col_width = 2;

    widths: []const usize,

    pub fn init(alloc: std.mem.Allocator, records: [][][]const u8, row_numbers: bool, term_width: usize) !Layout {
        const widths = try measure(alloc, records, row_numbers);
        defer alloc.free(widths);
        return autolayout(alloc, widths, term_width);
    }

    pub fn deinit(self: Layout, alloc: std.mem.Allocator) void {
        alloc.free(self.widths);
    }

    pub fn chromeWidth(self: Layout) usize {
        return self.widths.len * 3 + 1;
    }

    pub fn tableWidth(self: Layout) usize {
        return self.chromeWidth() + util.sum(usize, self.widths);
    }

    pub fn displayWidth(s: []const u8) usize {
        return std.unicode.utf8CountCodepoints(s) catch s.len;
    }
};

// measure the max width of each column, including row numbers
pub fn measure(alloc: std.mem.Allocator, records: [][][]const u8, row_numbers: bool) ![]usize {
    if (records.len <= 1 or records[0].len == 0) {
        return alloc.alloc(usize, 0);
    }

    var widths = std.ArrayList(usize).empty;
    try widths.appendNTimes(alloc, Layout.min_col_width, records[0].len);
    for (records) |row| {
        for (row, 0..) |value, ii| {
            widths.items[ii] = @max(widths.items[ii], Layout.displayWidth(value));
        }
    }
    if (row_numbers) {
        const ndigits = util.digits(usize, records.len - 1);
        try widths.insert(alloc, 0, @max(Layout.min_col_width, ndigits));
    }
    return widths.toOwnedSlice(alloc);
}

pub fn autolayout(alloc: std.mem.Allocator, widths: []const usize, term_width: usize) !Layout {
    if (widths.len == 0) {
        return .{ .widths = try alloc.alloc(usize, 0) };
    }

    const fudge: usize = 2;
    const lower_min: usize = 2;
    const lower_max: usize = 10;
    const input: Layout = .{ .widths = widths };

    const available = term_width -| (input.chromeWidth() + fudge);
    if (available == 0 or available >= input.tableWidth()) {
        return .{ .widths = try alloc.dupe(usize, widths) };
    }

    const lower_bound = std.math.clamp(available / widths.len, lower_min, lower_max);
    var min = try alloc.alloc(usize, widths.len);
    defer alloc.free(min);
    var max = try alloc.alloc(usize, widths.len);
    defer alloc.free(max);
    for (widths, 0..) |w, i| {
        min[i] = @min(w, lower_bound);
        max[i] = w;
    }

    const min_sum = util.sum(usize, min);
    const max_sum = util.sum(usize, max);
    if (available <= min_sum or max_sum == min_sum) {
        return .{ .widths = try alloc.dupe(usize, min) };
    }
    const ratio = @as(f64, @floatFromInt(available - min_sum)) /
        @as(f64, @floatFromInt(max_sum - min_sum));

    var diffs = try alloc.alloc(usize, widths.len);
    defer alloc.free(diffs);
    var layout = try alloc.alloc(usize, widths.len);
    errdefer alloc.free(layout);
    for (0..widths.len) |i| {
        diffs[i] = max[i] - min[i];
        layout[i] = min[i] + @as(usize, @intFromFloat(@as(f64, @floatFromInt(diffs[i])) * ratio));
    }

    const extra = available -| util.sum(usize, layout);
    if (extra > 0) {
        const indexes = try alloc.alloc(usize, widths.len);
        defer alloc.free(indexes);
        for (indexes, 0..) |*x, i| x.* = i;
        std.sort.block(usize, indexes, diffs, struct {
            fn lessThan(ctx: []usize, a: usize, b: usize) bool {
                return ctx[b] < ctx[a];
            }
        }.lessThan);

        const take = @min(extra, indexes.len);
        for (0..take) |k| {
            layout[indexes[k]] += 1;
        }
    }

    return .{ .widths = layout };
}

//
// tests
//

test "layout" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const input = Layout{ .widths = &[_]usize{ 32, 20, 10 } };

    const l1 = try autolayout(alloc, input.widths, 100);
    defer l1.deinit(alloc);
    try std.testing.expectEqualSlices(usize, input.widths, l1.widths);

    const l2 = try autolayout(alloc, input.widths, 50);
    defer l2.deinit(alloc);
    try std.testing.expectEqualSlices(usize, &[_]usize{ 16, 12, 10 }, l2.widths);
}

test "layout handles tiny terminals without underflow" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const input = Layout{ .widths = &[_]usize{ 8, 8, 8, 8, 8, 8, 8, 8 } };

    const l = try autolayout(alloc, input.widths, 40);
    defer l.deinit(alloc);
    try std.testing.expectEqual(input.widths.len, l.widths.len);
}

test "measure includes row numbers and unicode width" {
    const alloc = std.testing.allocator;
    var row1 = [_][]const u8{ "a", "éé" };
    var row2 = [_][]const u8{ "10", "x" };
    var records = [_][][]const u8{ &row1, &row2 };
    const widths = try measure(alloc, &records, true);
    defer alloc.free(widths);

    try std.testing.expectEqualSlices(usize, &[_]usize{ 2, 2, 2 }, widths);
}

test "measure returns empty layout for empty table" {
    const alloc = std.testing.allocator;
    var row = [_][]const u8{""};
    var records = [_][][]const u8{&row};
    const widths = try measure(alloc, &records, false);
    defer alloc.free(widths);

    try std.testing.expectEqual(0, widths.len);
}

test "autolayout keeps widths when term width exactly fits" {
    const alloc = std.testing.allocator;
    const input = Layout{ .widths = &[_]usize{ 7, 9, 11 } };
    const exact = input.tableWidth() + 2;
    const out = try autolayout(alloc, input.widths, exact);
    defer out.deinit(alloc);

    try std.testing.expectEqualSlices(usize, input.widths, out.widths);
}

test "autolayout handles empty widths" {
    const alloc = std.testing.allocator;
    const input = Layout{ .widths = &.{} };
    const out = try autolayout(alloc, input.widths, 80);
    defer out.deinit(alloc);

    try std.testing.expectEqual(0, out.widths.len);
}

const std = @import("std");
const util = @import("util.zig");
