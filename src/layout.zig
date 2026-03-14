//
// measure records to determine max width, then fit into term_width
//

pub const Layout = struct {
    widths: []const usize,

    pub fn init(table: *Table) !Layout {
        const measured = try measure(table.alloc, table.csv.rows, table.config.row_numbers);
        defer table.alloc.free(measured);
        const widths = try autolayout(table.alloc, measured, table.termWidth());
        return .{ .widths = widths };
    }

    pub fn deinit(self: Layout, alloc: std.mem.Allocator) void {
        alloc.free(self.widths);
    }

    // how many chars do we need for the non-data stuff? (borders/whitespace)
    pub fn chromeWidth(self: Layout) usize {
        return self.widths.len * 3 + 1;
    }

    // how wide is this table?
    pub fn tableWidth(self: Layout) usize {
        return self.chromeWidth() + util.sum(usize, self.widths);
    }
};

// measure the max width of each column, including row number col if any
fn measure(alloc: std.mem.Allocator, records: types.Rows, row_numbers: bool) ![]usize {
    const min_col_width = 2;

    if (records.len <= 1 or records[0].len == 0) {
        return alloc.alloc(usize, 0);
    }

    var widths = std.ArrayList(usize).empty;
    try widths.appendNTimes(alloc, min_col_width, records[0].len);
    for (records) |row| {
        for (row, 0..) |value, ii| {
            widths.items[ii] = @max(widths.items[ii], util.displayWidth(value));
        }
    }
    if (row_numbers) {
        const ndigits = util.digits(usize, records.len - 1);
        try widths.insert(alloc, 0, @max(min_col_width, ndigits));
    }
    return widths.toOwnedSlice(alloc);
}

// fit widths into term_width. this is similar to the HTML table layout algo
fn autolayout(alloc: std.mem.Allocator, widths: []const usize, term_width: usize) ![]usize {
    if (widths.len == 0) {
        return try alloc.alloc(usize, 0);
    }

    // a little breathing room on the right side, which is nice visually and
    // helps with minor terminal layout snafus
    const fudge: usize = 2;

    // is the terminal big enough to contain the table without truncation?
    const input: Layout = .{ .widths = widths };
    const available = term_width -| (input.chromeWidth() + fudge);
    if (available >= input.tableWidth()) {
        return try alloc.dupe(usize, widths);
    }

    // what is the lower bound for a column width? 2 is pretty severe, let it
    // grow up to 10 if we don't have a lot of columns.
    const lower_min: usize = 2;
    const lower_max: usize = 10;
    const lower_bound = std.math.clamp(available / widths.len, lower_min, lower_max);

    // calculate min & max for each column. min is the width of the widest cell
    // or lower_bound, whichever is smaller. max is the width of the widest
    // cell.
    var min = try alloc.alloc(usize, widths.len);
    defer alloc.free(min);
    var max = try alloc.alloc(usize, widths.len);
    defer alloc.free(max);
    for (widths, 0..) |w, i| {
        min[i] = @min(w, lower_bound);
        max[i] = w;
    }

    // calculate the ratio betweein min/max
    const min_sum = util.sum(usize, min);
    const max_sum = util.sum(usize, max);
    if (available <= min_sum or max_sum == min_sum) {
        return try alloc.dupe(usize, min);
    }
    const ratio = @as(f64, @floatFromInt(available - min_sum)) /
        @as(f64, @floatFromInt(max_sum - min_sum));

    // shrink each column by ratio
    var diffs = try alloc.alloc(usize, widths.len);
    defer alloc.free(diffs);
    var layout = try alloc.alloc(usize, widths.len);
    errdefer alloc.free(layout);
    for (0..widths.len) |i| {
        diffs[i] = max[i] - min[i];
        layout[i] = min[i] + @as(usize, @intFromFloat(@as(f64, @floatFromInt(diffs[i])) * ratio));
    }

    // due to rounding, there might be a few extra chars. hand those out too
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

    return layout;
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
    defer alloc.free(l1);
    try std.testing.expectEqualSlices(usize, input.widths, l1);

    const l2 = try autolayout(alloc, input.widths, 50);
    defer alloc.free(l2);
    try std.testing.expectEqualSlices(usize, &[_]usize{ 16, 12, 10 }, l2);
}

test "layout handles tiny terminals without underflow" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const input = Layout{ .widths = &[_]usize{ 8, 8, 8, 8, 8, 8, 8, 8 } };

    const l = try autolayout(alloc, input.widths, 40);
    defer alloc.free(l);
    try std.testing.expectEqual(input.widths.len, l.len);
}

test "measure includes row numbers and unicode width" {
    const alloc = std.testing.allocator;
    var row1 = [_]types.Field{ "a", "éé" };
    var row2 = [_]types.Field{ "10", "x" };
    var records = [_]types.Row{ &row1, &row2 };
    const widths = try measure(alloc, &records, true);
    defer alloc.free(widths);

    try std.testing.expectEqualSlices(usize, &[_]usize{ 2, 2, 2 }, widths);
}

test "measure returns empty layout for empty table" {
    const alloc = std.testing.allocator;
    var row = [_]types.Field{""};
    var records = [_]types.Row{&row};
    const widths = try measure(alloc, &records, false);
    defer alloc.free(widths);

    try std.testing.expectEqual(0, widths.len);
}

test "autolayout keeps widths when term width exactly fits" {
    const alloc = std.testing.allocator;
    const input = Layout{ .widths = &[_]usize{ 7, 9, 11 } };
    const exact = input.tableWidth() + 2;
    const out = try autolayout(alloc, input.widths, exact);
    defer alloc.free(out);

    try std.testing.expectEqualSlices(usize, input.widths, out);
}

test "autolayout handles empty widths" {
    const alloc = std.testing.allocator;
    const input = Layout{ .widths = &.{} };
    const out = try autolayout(alloc, input.widths, 80);
    defer alloc.free(out);

    try std.testing.expectEqual(0, out.len);
}

const std = @import("std");
const Table = @import("table.zig").Table;
const types = @import("types.zig");
const util = @import("util.zig");
