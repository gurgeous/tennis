// A column owns any formatted numeric cells and measures/inferes against visible rows only.

pub const Column = struct {
    table: *const Table,
    name: []const u8,
    index: usize,
    width: usize = 0, // how wide is this column?
    type: ColumnType = .string, // what does it contain?
    formatted: ?[]Field = null, // numerics get formatted in here

    pub fn init(table: *const Table, index: usize) !Column {
        var column: Column = .{
            .table = table,
            .name = table.headers()[index],
            .index = index,
        };

        // infer/format if not --vanilla
        if (!table.config.vanilla) {
            column.type = column.inferColumnType();
            switch (column.type) {
                .float => try column.formatColumn(formatFloat),
                .int => try column.formatColumn(formatInt),
                .string => {},
            }
        }

        // now that we've formatted, measure width
        column.width = column.measure();

        return column;
    }

    pub fn deinit(self: Column, alloc: std.mem.Allocator) void {
        if (self.formatted) |fields| {
            for (fields) |formatted| alloc.free(formatted);
            alloc.free(fields);
        }
    }

    //
    // accessors
    //

    pub fn iterator(self: Column) ColumnIterator {
        return .init(self.table, self.index);
    }

    pub fn field(self: Column, visible_index: usize) Field {
        if (self.formatted) |fields| return fields[visible_index];
        return self.table.rows()[self.table.visibleRow(visible_index)][self.index];
    }

    //
    // measure/infer
    //

    fn measure(self: Column) usize {
        var width = doomicode.displayWidth(self.name);
        for (0..self.table.visibleRowCount()) |visible_index| {
            width = @max(width, doomicode.displayWidth(self.field(visible_index)));
        }
        return width;
    }

    fn inferColumnType(self: Column) ColumnType {
        var floats: bool = false;
        var ints: bool = false;

        var it = self.iterator();
        while (it.next()) |value| {
            // ignore blanks
            if (value.len == 0) continue;

            if (int.isInt(value)) {
                ints = true;
                continue;
            }
            if (float.isFloat(value)) {
                floats = true;
                continue;
            }

            // early exit if we hit a string
            return .string;
        }

        if (floats) return .float;
        if (ints) return .int;
        return .string;
    }

    //
    // format
    //

    fn formatColumn(
        self: *Column,
        comptime formatter: fn (*Column, std.mem.Allocator, []const u8) anyerror![]u8,
    ) !void {
        const alloc = self.table.alloc;
        const fields = try alloc.alloc(Field, self.table.visibleRowCount());
        errdefer alloc.free(fields);

        var ii: usize = 0;
        errdefer {
            for (fields[0..ii]) |formatted| alloc.free(formatted);
        }
        var it = self.iterator();
        while (it.next()) |raw| : (ii += 1) {
            fields[ii] = try formatter(self, alloc, raw);
        }
        self.formatted = fields;
    }

    fn formatInt(self: *Column, alloc: std.mem.Allocator, raw: []const u8) ![]u8 {
        _ = self;
        return int.intFormat(alloc, raw);
    }

    fn formatFloat(self: *Column, alloc: std.mem.Allocator, raw: []const u8) ![]u8 {
        return float.floatFormat(alloc, raw, self.table.config.digits);
    }
};

pub const ColumnType = enum { int, float, string };

//
// iterator
//

pub const ColumnIterator = struct {
    table: *const Table,
    col: usize,
    visible_row: usize = 0,

    pub fn init(table: *const Table, col: usize) ColumnIterator {
        return .{ .table = table, .col = col };
    }

    pub fn next(self: *ColumnIterator) ?Field {
        if (self.visible_row >= self.table.visibleRowCount()) return null;
        const field = self.table.rows()[self.table.visibleRow(self.visible_row)][self.col];
        self.visible_row += 1;
        return field;
    }
};

//
// tests
//

test "column init stores table header and index" {
    var in = std.io.fixedBufferStream("a,b\nc,d\n");
    const table = try Table.init(std.testing.allocator, .{}, in.reader());
    defer table.deinit();

    const column = table.column(1);
    try std.testing.expectEqual(table, column.table);
    try std.testing.expectEqualStrings("b", column.name);
    try std.testing.expectEqual(@as(usize, 1), column.index);
    try std.testing.expectEqual(@as(usize, 1), column.width);
    try std.testing.expectEqual(ColumnType.string, column.type);
}

test "column vanilla skips inference and formatting" {
    var in = std.io.fixedBufferStream("a\n1234\n");
    const table = try Table.init(std.testing.allocator, .{ .vanilla = true }, in.reader());
    defer table.deinit();

    try std.testing.expectEqual(ColumnType.string, table.column(0).type);
    try std.testing.expectEqualStrings("1234", table.column(0).field(0));
    try std.testing.expectEqual(@as(usize, 4), table.column(0).width);
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

test "column tail formatting and width use visible rows" {
    var in = std.io.fixedBufferStream("a,b\nsuper-wide,1\nok,2\n");
    const table = try Table.init(std.testing.allocator, .{ .tail = 1 }, in.reader());
    defer table.deinit();

    try std.testing.expectEqualStrings("ok", table.column(0).field(0));
    try std.testing.expectEqual(@as(usize, 2), table.column(0).width);
    try std.testing.expectEqualStrings("2", table.column(1).field(0));
}

test "column measures widest header or field" {
    var in = std.io.fixedBufferStream("alpha,b\nx,longer\n");
    const table = try Table.init(std.testing.allocator, .{}, in.reader());
    defer table.deinit();

    try std.testing.expectEqual(@as(usize, 5), table.column(0).width);
    try std.testing.expectEqual(@as(usize, 6), table.column(1).width);
}

test "column int width includes delimiters" {
    var in = std.io.fixedBufferStream("a\n1234\n");
    const table = try Table.init(std.testing.allocator, .{}, in.reader());
    defer table.deinit();

    try std.testing.expectEqual(@as(usize, 5), table.column(0).width);
}

test "column float width includes delimiters and precision" {
    var in = std.io.fixedBufferStream("a\n1234.0\n");
    const table = try Table.init(std.testing.allocator, .{}, in.reader());
    defer table.deinit();

    try std.testing.expectEqual(@as(usize, 9), table.column(0).width);
    try std.testing.expectEqualStrings("1,234.000", table.column(0).field(0));
}

test "column float formatting respects digits config" {
    var in = std.io.fixedBufferStream("a\n12.34567\n");
    const table = try Table.init(std.testing.allocator, .{ .digits = 2 }, in.reader());
    defer table.deinit();

    try std.testing.expectEqualStrings("12.34", table.column(0).field(0));
    try std.testing.expectEqual(@as(usize, 5), table.column(0).width);
}

test "column float formatting handles integer-looking and blank cells" {
    var in = std.io.fixedBufferStream("a,b\n64,\n61.5,\n,\n");
    const table = try Table.init(std.testing.allocator, .{}, in.reader());
    defer table.deinit();

    try std.testing.expectEqual(ColumnType.float, table.column(0).type);
    try std.testing.expectEqualStrings("64.000", table.column(0).field(0));
    try std.testing.expectEqualStrings("61.500", table.column(0).field(1));
    try std.testing.expectEqualStrings("", table.column(0).field(2));
}

test "column infers data types" {
    var in = std.io.fixedBufferStream("a,b,c\n1,12.5,foo\n22,3.0,barbaz\n");
    const table = try Table.init(std.testing.allocator, .{}, in.reader());
    defer table.deinit();

    try std.testing.expectEqual(ColumnType.int, table.column(0).type);
    try std.testing.expectEqual(ColumnType.float, table.column(1).type);
    try std.testing.expectEqual(ColumnType.string, table.column(2).type);
}

test "column inference ignores blanks and scans all rows" {
    var buf = std.ArrayList(u8).empty;
    defer buf.deinit(std.testing.allocator);

    try buf.appendSlice(std.testing.allocator, "a,b\n");
    for (0..100) |ii| {
        try buf.writer(std.testing.allocator).print("{d},\n", .{ii});
    }
    try buf.appendSlice(std.testing.allocator, "not-a-number,\n");

    var in = std.io.fixedBufferStream(buf.items);
    const table = try Table.init(std.testing.allocator, .{}, in.reader());
    defer table.deinit();

    try std.testing.expectEqual(ColumnType.string, table.column(0).type);
    try std.testing.expectEqual(ColumnType.string, table.column(1).type);
}

const doomicode = @import("doomicode.zig");
const Field = @import("types.zig").Field;
const float = @import("float.zig");
const int = @import("int.zig");
const std = @import("std");
const Table = @import("table.zig").Table;
