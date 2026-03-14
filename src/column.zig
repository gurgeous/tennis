pub const Column = struct {
    table: *const Table,
    name: []const u8,
    index: usize,
    width: usize = 0,

    pub fn init(table: *const Table, index: usize) Column {
        var column: Column = .{
            .table = table,
            .name = table.headers()[index],
            .index = index,
        };
        column.width = column.measure();
        return column;
    }

    pub fn iterator(self: Column) ColumnIterator {
        return .init(self.table.rows(), self.index);
    }

    fn measure(self: Column) usize {
        var width = util.displayWidth(self.name);
        var it = self.iterator();
        while (it.next()) |f| {
            width = @max(width, util.displayWidth(f));
        }
        return width;
    }
};

pub const ColumnIterator = struct {
    rows: Rows,
    col: usize,
    row: usize = 0,

    pub fn init(rows: Rows, col: usize) ColumnIterator {
        return .{ .rows = rows, .col = col };
    }

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
    try std.testing.expectEqualStrings("b", column.name);
    try std.testing.expectEqual(@as(usize, 1), column.index);
    try std.testing.expectEqual(@as(usize, 1), column.width);
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

test "column measures widest header or field" {
    var in = std.io.fixedBufferStream("alpha,b\nx,longer\n");
    const table = try Table.init(std.testing.allocator, .{}, in.reader());
    defer table.deinit();

    try std.testing.expectEqual(@as(usize, 5), table.column(0).width);
    try std.testing.expectEqual(@as(usize, 6), table.column(1).width);
}

const std = @import("std");
const Table = @import("table.zig").Table;
const Field = @import("types.zig").Field;
const Rows = @import("types.zig").Rows;
const util = @import("util.zig");
