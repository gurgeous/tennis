//
// measure records to determine max width, then fit into term_width
//

// Final per-column widths used by the renderer.
pub const Layout = struct {
    widths: []const usize,

    // Measure the table and choose per-column widths.
    pub fn init(table: *Table) !Layout {
        return .{ .widths = try autolayout(table) };
    }

    // Release the owned width array.
    pub fn deinit(self: Layout, alloc: std.mem.Allocator) void {
        alloc.free(self.widths);
    }

    // Return the total width of data cells only.
    pub fn dataWidth(self: Layout) usize {
        return util.sum(usize, self.widths);
    }

    // how many chars do we need for the non-data stuff? (borders/whitespace)
    // Return the total width contributed by borders and separators.
    pub fn chromeWidth(self: Layout) usize {
        return self.widths.len * 3 + 1;
    }

    // how wide is this table?
    // Return the full rendered table width.
    pub fn tableWidth(self: Layout) usize {
        return self.chromeWidth() + self.dataWidth();
    }
};

// Fit measured column widths into the available terminal width.
fn autolayout(table: *Table) ![]usize {
    const alloc = table.alloc;
    if (table.isEmpty()) return alloc.alloc(usize, 0);

    // measure staring col widths
    const widths = try measure(table);
    defer alloc.free(widths);

    // a little breathing room on the right side, which is nice visually and
    // helps with minor terminal layout snafus
    const fudge = 2;

    // is the terminal big enough to contain the table without truncation?
    const input: Layout = .{ .widths = widths };
    const term_width = table.termWidth();
    const available = term_width -| (input.chromeWidth() + fudge);
    if (available >= input.dataWidth()) {
        return try alloc.dupe(usize, widths);
    }

    // what is the lower bound for a column width? 2 is pretty severe, let it
    // grow up to 10 if we don't have a lot of columns.
    const lower_min = 2;
    const lower_max = 10;
    const lower_bound = std.math.clamp(available / widths.len, lower_min, lower_max);

    // calculate min & max for each column. min is the width of the widest cell
    // or lower_bound, whichever is smaller. max is the width of the widest
    // cell.
    var min = try alloc.alloc(usize, widths.len);
    defer alloc.free(min);
    for (widths, 0..) |w, ii| {
        min[ii] = @min(w, lower_bound);
    }
    const max = widths;

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
            // Sort indexes by descending spare width.
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

// Measure the natural width of every visible column.
fn measure(table: *const Table) ![]usize {
    const alloc = table.alloc;

    // naive widths
    var widths = std.ArrayList(usize).empty;
    if (table.config.row_numbers) {
        try widths.append(alloc, util.digits(usize, table.visibleLastRowNumber()));
    }
    for (table.columns) |column| {
        try widths.append(alloc, column.width);
    }

    // min 2
    const min_col_width = 2;
    for (widths.items, 0..) |_, i| {
        widths.items[i] = @max(widths.items[i], min_col_width);
    }

    return widths.toOwnedSlice(alloc);
}

//
// testing
//

test "autolayout cases" {
    const cases = [_]struct {
        config: types.Config,
        input: []const u8,
        want: []const usize,
    }{
        .{ .config = .{ .width = 100 }, .input = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa,bbbbbbbbbbbbbbbbbbbb,cccccccccc\nx,y,z\n", .want = &.{ 32, 20, 10 } },
        .{ .config = .{ .width = 50 }, .input = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa,bbbbbbbbbbbbbbbbbbbb,cccccccccc\nx,y,z\n", .want = &.{ 16, 12, 10 } },
        .{ .config = .{ .width = 39 }, .input = "1234567,123456789,12345678901\nx,y,z\n", .want = &.{ 7, 9, 11 } },
        .{ .config = .{ .width = 80 }, .input = "", .want = &.{} },
    };

    for (cases) |tc| try expectAutolayout(tc.config, tc.input, tc.want);
}

test "layout handles tiny terminals without underflow" {
    const table = try Table.initCsv(testing.allocator, .{ .width = 40 }, "12345678,12345678,12345678,12345678,12345678,12345678,12345678,12345678\nx,x,x,x,x,x,x,x\n");
    defer table.deinit();
    const l = try autolayout(table);
    defer testing.allocator.free(l);
    try testing.expectEqual(@as(usize, 8), l.len);
}

test "measure includes row numbers and unicode width" {
    const table = try Table.initCsv(testing.allocator, .{ .row_numbers = true }, "a,\xc3\xa9\xc3\xa9\n10,x\n");
    defer table.deinit();
    const widths = try measure(table);
    defer testing.allocator.free(widths);

    try testing.expectEqualSlices(usize, &[_]usize{ 2, 2, 2 }, widths);
}

test "measure returns empty layout for empty inputs" {
    try expectMeasure(.{}, "", &.{});
    try expectMeasure(.{}, "a,b\n", &.{});
}

test "measure ignores empty data cell width" {
    const table = try Table.initCsv(testing.allocator, .{}, "alpha,beta\n,xyz\n");
    defer table.deinit();
    const widths = try measure(table);
    defer testing.allocator.free(widths);

    try testing.expectEqualSlices(usize, &[_]usize{ 5, 4 }, widths);
}

fn expectAutolayout(config: types.Config, input: []const u8, want: []const usize) !void {
    const table = try Table.initCsv(testing.allocator, config, input);
    defer table.deinit();
    const got = try autolayout(table);
    defer testing.allocator.free(got);
    try testing.expectEqualSlices(usize, want, got);
}

fn expectMeasure(config: types.Config, input: []const u8, want: []const usize) !void {
    const table = try Table.initCsv(testing.allocator, config, input);
    defer table.deinit();
    const got = try measure(table);
    defer testing.allocator.free(got);
    try testing.expectEqualSlices(usize, want, got);
}

const std = @import("std");
const testing = std.testing;
const Table = @import("table.zig").Table;
const types = @import("types.zig");
const util = @import("util.zig");
