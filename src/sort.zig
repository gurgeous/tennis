// Parse and apply stable row sorting plus column selection from header specs.

// Resolved sort columns ready to apply to table row indexes.
pub const Sort = struct {
    cols: []usize,

    // Parse a comma-separated sort spec into resolved header indexes.
    pub fn init(alloc: std.mem.Allocator, headers: Row, spec: []const u8) !Sort {
        return .{ .cols = resolveColumns(alloc, headers, spec) catch return error.InvalidSort };
    }

    // Release the resolved sort column list.
    pub fn deinit(self: Sort, alloc: std.mem.Allocator) void {
        alloc.free(self.cols);
    }

    // Apply the configured stable row ordering to the display index list.
    pub fn apply(self: Sort, data: Data, row_order: []usize) void {
        std.sort.block(usize, row_order, SortCtx{
            .data = data,
            .cols = self.cols,
        }, SortCtx.lessThan);
    }
};

// Resolved visible columns ready to apply to table headers and cells.
pub const Select = struct {
    cols: []usize,

    // Parse a comma-separated select spec into resolved header indexes.
    pub fn init(alloc: std.mem.Allocator, headers: Row, spec: []const u8) !Select {
        return .{ .cols = resolveColumns(alloc, headers, spec) catch return error.InvalidSelect };
    }

    // Release the resolved select column list.
    pub fn deinit(self: Select, alloc: std.mem.Allocator) void {
        alloc.free(self.cols);
    }
};

// Resolve a comma-separated column spec into header indexes.
fn resolveColumns(alloc: std.mem.Allocator, headers: Row, spec: []const u8) ![]usize {
    var cols: std.ArrayList(usize) = .empty;
    defer cols.deinit(alloc);

    var it = std.mem.splitScalar(u8, spec, ',');
    while (it.next()) |raw| {
        const name = util.strip(u8, raw);
        if (name.len == 0) return error.InvalidColumns;
        for (headers, 0..) |header, ii| {
            if (std.ascii.eqlIgnoreCase(header, name)) {
                try cols.append(alloc, ii);
                break;
            }
        } else return error.InvalidColumns;
    }

    return cols.toOwnedSlice(alloc);
}

// Build the user-facing error text for invalid sort specs.
pub fn sortErrorString(alloc: std.mem.Allocator, headers: Row) ![]u8 {
    return errorString(alloc, headers, "sort");
}

// Build the user-facing error text for invalid select specs.
pub fn selectErrorString(alloc: std.mem.Allocator, headers: Row) ![]u8 {
    return errorString(alloc, headers, "select");
}

// Build the user-facing error text for invalid column specs.
fn errorString(alloc: std.mem.Allocator, headers: Row, flag: []const u8) ![]u8 {
    var columns: std.ArrayList(u8) = .empty;
    defer columns.deinit(alloc);
    for (headers, 0..) |header, ii| {
        if (ii > 0) try columns.appendSlice(alloc, ", ");
        try columns.appendSlice(alloc, header);
    }

    return std.fmt.allocPrint(alloc,
        \\--{s} didn't look right, should be a comma-separated list of columns.
        \\column names: {s}
    , .{ flag, columns.items });
}

// Comparator context for sorting row indexes against loaded data.
const SortCtx = struct {
    data: Data,
    cols: []const usize,

    // Compare two data-row indexes using natural ordering over the sort columns.
    fn lessThan(ctx: @This(), lhs: usize, rhs: usize) bool {
        const a = ctx.data.row(lhs + 1);
        const b = ctx.data.row(rhs + 1);
        for (ctx.cols) |col| {
            switch (natsort.order(a[col], b[col])) {
                .lt => return true,
                .gt => return false,
                .eq => {},
            }
        }
        return lhs < rhs;
    }
};

//
// testing
//

test "Sort.init resolves case insensitive header names" {
    const sort = try Sort.init(testing.allocator, &.{ "name", "score" }, " NAME , score ");
    defer sort.deinit(testing.allocator);

    try testing.expectEqual(@as(usize, 2), sort.cols.len);
    try testing.expectEqual(@as(usize, 0), sort.cols[0]);
    try testing.expectEqual(@as(usize, 1), sort.cols[1]);
}

test "Select.init supports reordering and duplicates" {
    const select = try Select.init(testing.allocator, &.{ "name", "score" }, "score,name,score");
    defer select.deinit(testing.allocator);

    try testing.expectEqualSlices(usize, &.{ 1, 0, 1 }, select.cols);
}

test "column specs reject bad input" {
    try testing.expectError(error.InvalidSort, Sort.init(testing.allocator, &.{ "name", "score" }, ""));
    try testing.expectError(error.InvalidSort, Sort.init(testing.allocator, &.{ "name", "score" }, "name,"));
    try testing.expectError(error.InvalidSelect, Select.init(testing.allocator, &.{ "name", "score" }, "bogus"));
}

test "error strings include headers" {
    const sort_msg = try sortErrorString(testing.allocator, &.{ "name", "score" });
    defer testing.allocator.free(sort_msg);
    try testing.expect(std.mem.indexOf(u8, sort_msg, "name, score") != null);
    try testing.expect(std.mem.indexOf(u8, sort_msg, "--sort") != null);

    const select_msg = try selectErrorString(testing.allocator, &.{ "name", "score" });
    defer testing.allocator.free(select_msg);
    try testing.expect(std.mem.indexOf(u8, select_msg, "name, score") != null);
    try testing.expect(std.mem.indexOf(u8, select_msg, "--select") != null);
}

test "Sort.apply preserves original order for equal values" {
    const alloc = testing.allocator;
    const rows = try alloc.alloc(DataRow, 4);
    errdefer alloc.free(rows);
    rows[0] = try DataRow.init(alloc, &.{ "name", "score" });
    errdefer rows[0].deinit(alloc);
    rows[1] = try DataRow.init(alloc, &.{ "alice", "1" });
    errdefer rows[1].deinit(alloc);
    rows[2] = try DataRow.init(alloc, &.{ "bob", "1" });
    errdefer rows[2].deinit(alloc);
    rows[3] = try DataRow.init(alloc, &.{ "cara", "2" });
    errdefer rows[3].deinit(alloc);

    const data: Data = .{ .rows = rows };
    defer data.deinit(alloc);

    var order = [_]usize{ 0, 1, 2 };
    const sort = try Sort.init(alloc, data.headers(), "score");
    defer sort.deinit(alloc);
    sort.apply(data, &order);

    try testing.expectEqualSlices(usize, &.{ 0, 1, 2 }, &order);
}

test "Sort.apply uses natural ordering for numeric strings and fractions" {
    const alloc = testing.allocator;
    const rows = try alloc.alloc(DataRow, 5);
    errdefer alloc.free(rows);
    rows[0] = try DataRow.init(alloc, &.{ "name", "score" });
    errdefer rows[0].deinit(alloc);
    rows[1] = try DataRow.init(alloc, &.{ "a", "10" });
    errdefer rows[1].deinit(alloc);
    rows[2] = try DataRow.init(alloc, &.{ "b", "2" });
    errdefer rows[2].deinit(alloc);
    rows[3] = try DataRow.init(alloc, &.{ "c", "1.02" });
    errdefer rows[3].deinit(alloc);
    rows[4] = try DataRow.init(alloc, &.{ "d", "1.010" });
    errdefer rows[4].deinit(alloc);

    const data: Data = .{ .rows = rows };
    defer data.deinit(alloc);

    var order = [_]usize{ 0, 1, 2, 3 };
    const sort = try Sort.init(alloc, data.headers(), "score");
    defer sort.deinit(alloc);
    sort.apply(data, &order);

    try testing.expectEqualSlices(usize, &.{ 3, 2, 1, 0 }, &order);
}

const Data = @import("data.zig").Data;
const DataRow = @import("data.zig").DataRow;
const natsort = @import("natsort.zig");
const Row = @import("types.zig").Row;
const std = @import("std");
const testing = std.testing;
const util = @import("util.zig");
