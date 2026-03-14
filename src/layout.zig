//
// measure records to determine max width, then fit into term_width
//

pub const Layout = struct {
    widths: []const usize,

    pub fn init(table: *Table) !Layout {
        return .{ .widths = try autolayout(table) };
    }

    pub fn deinit(self: Layout, alloc: std.mem.Allocator) void {
        alloc.free(self.widths);
    }

    pub fn dataWidth(self: Layout) usize {
        return util.sum(usize, self.widths);
    }

    // how many chars do we need for the non-data stuff? (borders/whitespace)
    pub fn chromeWidth(self: Layout) usize {
        return self.widths.len * 3 + 1;
    }

    // how wide is this table?
    pub fn tableWidth(self: Layout) usize {
        return self.chromeWidth() + self.dataWidth();
    }
};

// measure the max width of each column, including row number col if any
fn measure(table: *const Table) ![]usize {
    const alloc = table.alloc;
    const min_col_width = 2;
    const headers = table.headers();
    const rows = table.rows();
    if (headers.len == 0 or rows.len == 0) {
        return alloc.alloc(usize, 0);
    }

    var widths = std.ArrayList(usize).empty;
    try widths.appendNTimes(alloc, min_col_width, headers.len);
    for (headers, 0..) |value, ii| {
        widths.items[ii] = @max(widths.items[ii], util.displayWidth(value));
    }
    for (rows) |row| {
        for (row, 0..) |value, ii| {
            widths.items[ii] = @max(widths.items[ii], util.displayWidth(value));
        }
    }
    if (table.config.row_numbers) {
        const ndigits = util.digits(usize, table.nrows());
        try widths.insert(alloc, 0, @max(min_col_width, ndigits));
    }
    return widths.toOwnedSlice(alloc);
}

// fit widths into term_width. this is similar to the HTML table layout algo
fn autolayout(table: *Table) ![]usize {
    const alloc = table.alloc;
    const widths = try measure(table);
    defer alloc.free(widths);
    const term_width = table.termWidth();

    if (widths.len == 0) {
        return try alloc.alloc(usize, 0);
    }

    // a little breathing room on the right side, which is nice visually and
    // helps with minor terminal layout snafus
    const fudge: usize = 2;

    // is the terminal big enough to contain the table without truncation?
    const input: Layout = .{ .widths = widths };
    const available = term_width -| (input.chromeWidth() + fudge);
    if (available >= input.dataWidth()) {
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
    var in1 = std.io.fixedBufferStream("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa,bbbbbbbbbbbbbbbbbbbb,cccccccccc\nx,y,z\n");
    const table1 = try Table.init(std.testing.allocator, .{ .width = 100 }, in1.reader());
    defer table1.deinit();
    const l1 = try autolayout(table1);
    defer std.testing.allocator.free(l1);
    try std.testing.expectEqualSlices(usize, &[_]usize{ 32, 20, 10 }, l1);

    var in2 = std.io.fixedBufferStream("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa,bbbbbbbbbbbbbbbbbbbb,cccccccccc\nx,y,z\n");
    const table2 = try Table.init(std.testing.allocator, .{ .width = 50 }, in2.reader());
    defer table2.deinit();
    const l2 = try autolayout(table2);
    defer std.testing.allocator.free(l2);
    try std.testing.expectEqualSlices(usize, &[_]usize{ 16, 12, 10 }, l2);
}

test "layout handles tiny terminals without underflow" {
    var in = std.io.fixedBufferStream("12345678,12345678,12345678,12345678,12345678,12345678,12345678,12345678\nx,x,x,x,x,x,x,x\n");
    const table = try Table.init(std.testing.allocator, .{ .width = 40 }, in.reader());
    defer table.deinit();
    const l = try autolayout(table);
    defer std.testing.allocator.free(l);
    try std.testing.expectEqual(@as(usize, 8), l.len);
}

test "measure includes row numbers and unicode width" {
    var in = std.io.fixedBufferStream("a,\xc3\xa9\xc3\xa9\n10,x\n");
    const table = try Table.init(std.testing.allocator, .{ .row_numbers = true }, in.reader());
    defer table.deinit();
    const widths = try measure(table);
    defer std.testing.allocator.free(widths);

    try std.testing.expectEqualSlices(usize, &[_]usize{ 2, 2, 2 }, widths);
}

test "measure returns empty layout for empty table" {
    var in = std.io.fixedBufferStream("");
    const table = try Table.init(std.testing.allocator, .{}, in.reader());
    defer table.deinit();
    const widths = try measure(table);
    defer std.testing.allocator.free(widths);

    try std.testing.expectEqual(0, widths.len);
}

test "measure returns empty layout for header only table" {
    var in = std.io.fixedBufferStream("a,b\n");
    const table = try Table.init(std.testing.allocator, .{}, in.reader());
    defer table.deinit();
    const widths = try measure(table);
    defer std.testing.allocator.free(widths);

    try std.testing.expectEqual(0, widths.len);
}

test "measure ignores empty data cell width" {
    var in = std.io.fixedBufferStream("alpha,beta\n,xyz\n");
    const table = try Table.init(std.testing.allocator, .{}, in.reader());
    defer table.deinit();
    const widths = try measure(table);
    defer std.testing.allocator.free(widths);

    try std.testing.expectEqualSlices(usize, &[_]usize{ 5, 4 }, widths);
}

test "autolayout keeps widths when term width exactly fits" {
    var in = std.io.fixedBufferStream("1234567,123456789,12345678901\nx,y,z\n");
    const table = try Table.init(std.testing.allocator, .{ .width = 39 }, in.reader());
    defer table.deinit();
    const out = try autolayout(table);
    defer std.testing.allocator.free(out);

    try std.testing.expectEqualSlices(usize, &[_]usize{ 7, 9, 11 }, out);
}

test "autolayout handles empty widths" {
    var in = std.io.fixedBufferStream("");
    const table = try Table.init(std.testing.allocator, .{ .width = 80 }, in.reader());
    defer table.deinit();
    const out = try autolayout(table);
    defer std.testing.allocator.free(out);

    try std.testing.expectEqual(0, out.len);
}

const std = @import("std");
const Table = @import("table.zig").Table;
const util = @import("util.zig");
