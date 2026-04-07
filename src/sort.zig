// Apply stable row sorting from already-resolved header indexes.

// Resolved sort columns ready to apply to table row indexes.
pub const Sort = struct {
    cols: []usize,

    // Apply the configured stable row ordering to the display index list.
    pub fn apply(self: Sort, data: Data, row_order: []usize) void {
        std.sort.block(usize, row_order, SortCtx{
            .data = data,
            .cols = self.cols,
        }, SortCtx.lessThan);
    }
};

// Comparator context for sorting row indexes against loaded data.
const SortCtx = struct {
    data: Data,
    cols: []const usize,

    // Compare two data-row indexes using natural ordering over the sort columns.
    fn lessThan(ctx: @This(), lhs: usize, rhs: usize) bool {
        const a = ctx.data.row(lhs + 1);
        const b = ctx.data.row(rhs + 1);
        for (ctx.cols) |col| {
            switch (natsort.order(a[col], b[col], true)) {
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
    var cols = [_]usize{1};
    const sort: Sort = .{ .cols = cols[0..] };
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
    var cols = [_]usize{1};
    const sort: Sort = .{ .cols = cols[0..] };
    sort.apply(data, &order);

    try testing.expectEqualSlices(usize, &.{ 3, 2, 1, 0 }, &order);
}

test "Sort.apply ignores ASCII case while preserving stable ties" {
    const alloc = testing.allocator;
    const rows = try alloc.alloc(DataRow, 5);
    errdefer alloc.free(rows);
    rows[0] = try DataRow.init(alloc, &.{ "name", "score" });
    errdefer rows[0].deinit(alloc);
    rows[1] = try DataRow.init(alloc, &.{ "bob", "1" });
    errdefer rows[1].deinit(alloc);
    rows[2] = try DataRow.init(alloc, &.{ "Alice", "2" });
    errdefer rows[2].deinit(alloc);
    rows[3] = try DataRow.init(alloc, &.{ "alice", "3" });
    errdefer rows[3].deinit(alloc);
    rows[4] = try DataRow.init(alloc, &.{ "Cara", "4" });
    errdefer rows[4].deinit(alloc);

    const data: Data = .{ .rows = rows };
    defer data.deinit(alloc);

    var order = [_]usize{ 0, 1, 2, 3 };
    var cols = [_]usize{0};
    const sort: Sort = .{ .cols = cols[0..] };
    sort.apply(data, &order);

    try testing.expectEqualSlices(usize, &.{ 1, 2, 0, 3 }, &order);
}

const Data = @import("data.zig").Data;
const DataRow = @import("data.zig").DataRow;
const natsort = @import("natsort.zig");
const std = @import("std");
const testing = std.testing;
