pub const Column = struct {
    table: *const Table,
    index: usize,

    pub fn init(table: *const Table, index: usize) Column {
        return .{ .table = table, .index = index };
    }

    pub fn name(self: Column) []const u8 {
        return self.table.headers()[self.index];
    }

    pub fn iterator(self: Column) ColumnIterator {
        return .{ .rows = self.table.rows(), .col = self.index };
    }
};

pub const ColumnIterator = struct {
    rows: Rows,
    col: usize,
    row: usize = 0,

    pub fn next(self: *ColumnIterator) ?Field {
        if (self.row >= self.rows.len) return null;
        const field = self.rows[self.row][self.col];
        self.row += 1;
        return field;
    }
};

test "column init stores table header and index" {
    var in = std.io.fixedBufferStream("a,b\nc,d\n");
    const table = try Table.init(std.testing.allocator, .{}, in.reader());
    defer table.deinit();

    const column = table.column(1);
    try std.testing.expectEqual(table, column.table);
    try std.testing.expectEqualStrings("b", column.name());
    try std.testing.expectEqual(@as(usize, 1), column.index);
}

test "column iterator walks data rows only" {
    var in = std.io.fixedBufferStream("a,b\nc,d\ne,f\n");
    const table = try Table.init(std.testing.allocator, .{}, in.reader());
    defer table.deinit();

    var it = table.column(1).iterator();
    try std.testing.expectEqualStrings("d", it.next().?);
    try std.testing.expectEqualStrings("f", it.next().?);
    try std.testing.expectEqual(@as(?Field, null), it.next());
}

const std = @import("std");
const Table = @import("table.zig").Table;
const Field = @import("types.zig").Field;
const Rows = @import("types.zig").Rows;
