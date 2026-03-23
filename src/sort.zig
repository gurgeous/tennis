// Parse and apply stable row sorting from a comma-separated header list.

pub const Sort = struct {
    cols: []usize,

    pub fn init(alloc: std.mem.Allocator, headers: Row, spec: []const u8) !Sort {
        var cols: std.ArrayList(usize) = .empty;
        defer cols.deinit(alloc);

        var it = std.mem.splitScalar(u8, spec, ',');
        while (it.next()) |raw| {
            const name = util.strip(u8, raw);
            if (name.len == 0) return error.InvalidSort;
            for (headers, 0..) |header, ii| {
                if (std.ascii.eqlIgnoreCase(header, name)) {
                    try cols.append(alloc, ii);
                    break;
                }
            } else return error.InvalidSort;
        }

        if (cols.items.len == 0) return error.InvalidSort;
        return .{ .cols = try cols.toOwnedSlice(alloc) };
    }

    pub fn deinit(self: Sort, alloc: std.mem.Allocator) void {
        alloc.free(self.cols);
    }

    pub fn apply(self: Sort, data: Data, row_order: []usize) void {
        std.sort.block(usize, row_order, SortCtx{
            .data = data,
            .cols = self.cols,
        }, SortCtx.lessThan);
    }
};

pub fn validate(alloc: std.mem.Allocator, headers: Row, spec: []const u8) !void {
    const sort = try Sort.init(alloc, headers, spec);
    defer sort.deinit(alloc);
}

pub fn errorString(alloc: std.mem.Allocator, headers: Row) ![]u8 {
    var columns: std.ArrayList(u8) = .empty;
    defer columns.deinit(alloc);
    for (headers, 0..) |header, ii| {
        if (ii > 0) try columns.appendSlice(alloc, ", ");
        try columns.appendSlice(alloc, header);
    }
    return std.fmt.allocPrint(alloc, "Problem with --sort. Use a comma-separated list of headers. Columns: {s}", .{columns.items});
}

const SortCtx = struct {
    data: Data,
    cols: []const usize,

    fn lessThan(ctx: @This(), lhs: usize, rhs: usize) bool {
        const a = ctx.data.row(lhs + 1);
        const b = ctx.data.row(rhs + 1);
        for (ctx.cols) |col| {
            switch (std.mem.order(u8, a[col], b[col])) {
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

test "Sort.init rejects bad sort specs" {
    try testing.expectError(error.InvalidSort, Sort.init(testing.allocator, &.{ "name", "score" }, ""));
    try testing.expectError(error.InvalidSort, Sort.init(testing.allocator, &.{ "name", "score" }, "name,"));
    try testing.expectError(error.InvalidSort, Sort.init(testing.allocator, &.{ "name", "score" }, "bogus"));
}

test "Sort.errorString includes headers" {
    const msg = try errorString(testing.allocator, &.{ "name", "score" });
    defer testing.allocator.free(msg);

    try testing.expect(std.mem.indexOf(u8, msg, "comma-separated list of headers") != null);
    try testing.expect(std.mem.indexOf(u8, msg, "name, score") != null);
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

const Data = @import("data.zig").Data;
const DataRow = @import("data.zig").DataRow;
const Row = @import("types.zig").Row;
const std = @import("std");
const testing = std.testing;
const util = @import("util.zig");
