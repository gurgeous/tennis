//
// measure records to determine max width, then fit into term_width
//

// Final per-column widths used by the renderer.
pub const Layout = struct {
    widths: []const usize,

    // Measure the table and choose per-column widths.
    pub fn init(table: *Table) !Layout {
        return .{ .widths = try layout(table) };
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

// Calculate table layout, returns column widths
fn layout(table: *Table) ![]usize {
    // 1. empty
    const alloc = table.alloc;
    if (table.isEmpty()) return alloc.alloc(usize, 0);

    // 2. min
    if (table.config.width == .min) return headerWidths(table);

    // 3. max
    const measured = try measureCells(table);
    defer alloc.free(measured);
    const ncols = measured.len;
    if (table.config.width == .max) return try alloc.dupe(usize, measured);

    //
    // This is the default, where we squeeze into termwidth (auto)
    //

    // a little breathing room on the right side, which is nice visually and
    // helps alleviate minor terminal layout snafus
    const fudge = 2;

    // is the terminal big enough to contain the table without truncation?
    const input: Layout = .{ .widths = measured };
    const term_width = table.termWidth();
    const available = term_width -| (input.chromeWidth() + fudge);
    if (available >= input.dataWidth()) {
        return try alloc.dupe(usize, measured);
    }

    // what is the lower bound for a column width? 2 is pretty severe, let it
    // grow up to 10 if we don't have a lot of columns.
    const lower_min = 2;
    const lower_max = 10;
    const lower_bound = std.math.clamp(available / measured.len, lower_min, lower_max);

    // calculate min & max for each column. min is the width of the widest cell
    // or lower_bound, whichever is smaller. max is the width of the widest
    // cell.
    var min = try alloc.alloc(usize, measured.len);
    defer alloc.free(min);
    for (measured, 0..) |w, ii| {
        min[ii] = @min(w, lower_bound);
    }
    const max = measured;

    // calculate the ratio betweein min/max
    const min_sum = util.sum(usize, min);
    const max_sum = util.sum(usize, max);
    if (available <= min_sum or max_sum == min_sum) {
        return try alloc.dupe(usize, min);
    }
    const ratio = @as(f64, @floatFromInt(available - min_sum)) /
        @as(f64, @floatFromInt(max_sum - min_sum));

    // shrink each column by ratio
    var diffs = try alloc.alloc(usize, ncols);
    defer alloc.free(diffs);
    var result = try alloc.alloc(usize, ncols);
    errdefer alloc.free(result);
    for (0..ncols) |i| {
        diffs[i] = max[i] - min[i];
        result[i] = min[i] + @as(usize, @intFromFloat(@as(f64, @floatFromInt(diffs[i])) * ratio));
    }

    // due to rounding, there might be a few extra chars. hand those out too
    const extra = available -| util.sum(usize, result);
    if (extra > 0) {
        const indexes = try util.range(alloc, ncols);
        defer alloc.free(indexes);
        std.sort.block(usize, indexes, diffs, struct {
            // Sort indexes by descending spare width.
            fn lessThan(ctx: []usize, a: usize, b: usize) bool {
                return ctx[b] < ctx[a];
            }
        }.lessThan);

        const take = @min(extra, indexes.len);
        for (0..take) |k| {
            result[indexes[k]] += 1;
        }
    }

    return result;
}

// Measure the natural width of every visible column.
fn measureCells(table: *const Table) ![]usize {
    const alloc = table.alloc;

    // naive widths
    var widths = std.ArrayList(usize).empty;
    if (table.config.row_numbers) {
        try widths.append(alloc, util.digits(usize, table.nrows()));
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

// Measure header widths without considering data rows.
fn headerWidths(table: *const Table) ![]usize {
    const alloc = table.alloc;
    var widths = std.ArrayList(usize).empty;
    errdefer widths.deinit(alloc);

    if (table.config.row_numbers) {
        try widths.append(alloc, util.digits(usize, table.nrows()));
    }
    for (table.headers()) |header| {
        try widths.append(alloc, @max(doomicode.displayWidth(header), 2));
    }
    return widths.toOwnedSlice(alloc);
}

//
// testing
//

test "layout cases" {
    const cases = [_]struct {
        config: types.Config,
        input: []const u8,
        want: []const usize,
    }{
        .{ .config = .{ .width = .{ .chars = 100 } }, .input = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa,bbbbbbbbbbbbbbbbbbbb,cccccccccc\nx,y,z\n", .want = &.{ 32, 20, 10 } },
        .{ .config = .{ .width = .{ .chars = 50 } }, .input = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa,bbbbbbbbbbbbbbbbbbbb,cccccccccc\nx,y,z\n", .want = &.{ 16, 12, 10 } },
        .{ .config = .{ .width = .{ .chars = 39 } }, .input = "1234567,123456789,12345678901\nx,y,z\n", .want = &.{ 7, 9, 11 } },
        .{ .config = .{ .width = .max }, .input = "1234567,123456789,12345678901\nx,y,z\n", .want = &.{ 7, 9, 11 } },
        .{ .config = .{ .width = .min }, .input = "alpha,beta,gamma\nx,y,z\n", .want = &.{ 5, 4, 5 } },
        .{ .config = .{ .width = .{ .chars = 80 } }, .input = "", .want = &.{} },
    };

    for (cases) |tc| try expectLayout(tc.config, tc.input, tc.want);
}

test "layout handles tiny terminals without underflow" {
    const table = try Table.initCsv(testing.allocator, .{ .width = .{ .chars = 40 } }, "12345678,12345678,12345678,12345678,12345678,12345678,12345678,12345678\nx,x,x,x,x,x,x,x\n");
    defer table.deinit();
    const l = try layout(table);
    defer testing.allocator.free(l);
    try testing.expectEqual(@as(usize, 8), l.len);
}

test "measure includes row numbers and unicode width" {
    const table = try Table.initCsv(testing.allocator, .{ .row_numbers = true }, "a,\xc3\xa9\xc3\xa9\n10,x\n");
    defer table.deinit();
    const widths = try measureCells(table);
    defer testing.allocator.free(widths);

    try testing.expectEqualSlices(usize, &[_]usize{ 2, 2, 2 }, widths);
}

test "headerWidths uses header labels" {
    const table = try Table.initCsv(testing.allocator, .{}, "alpha,b\nx,longlonglong\n");
    defer table.deinit();
    const widths = try headerWidths(table);
    defer testing.allocator.free(widths);

    try testing.expectEqualSlices(usize, &[_]usize{ 5, 2 }, widths);
}

test "measure returns empty layout for empty inputs" {
    try expectMeasure(.{}, "", &.{});
    try expectMeasure(.{}, "a,b\n", &.{});
}

test "measure ignores empty data cell width" {
    const table = try Table.initCsv(testing.allocator, .{}, "alpha,beta\n,xyz\n");
    defer table.deinit();
    const widths = try measureCells(table);
    defer testing.allocator.free(widths);

    try testing.expectEqualSlices(usize, &[_]usize{ 5, 4 }, widths);
}

fn expectLayout(config: types.Config, input: []const u8, want: []const usize) !void {
    const table = try Table.initCsv(testing.allocator, config, input);
    defer table.deinit();
    const got = try layout(table);
    defer testing.allocator.free(got);
    try testing.expectEqualSlices(usize, want, got);
}

fn expectMeasure(config: types.Config, input: []const u8, want: []const usize) !void {
    const table = try Table.initCsv(testing.allocator, config, input);
    defer table.deinit();
    const got = try measureCells(table);
    defer testing.allocator.free(got);
    try testing.expectEqualSlices(usize, want, got);
}

const doomicode = @import("doomicode.zig");
const std = @import("std");
const Table = @import("table.zig").Table;
const testing = std.testing;
const types = @import("types.zig");
const util = @import("util.zig");
