// A column owns any formatted numeric cells and measures/inferes against visible rows only.

// One measured and optionally formatted table column.
pub const Column = struct {
    table: *const Table,
    name: []const u8,
    index: usize,
    width: usize = 0, // how wide is this column?
    type: ColumnType = .string, // what does it contain?
    formatted: ?[]Field = null, // numerics get formatted in here

    // Build one measured column from the table's visible rows.
    pub fn init(table: *Table, index: usize) !Column {
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

    // Release any formatted numeric cells owned by this column.
    pub fn deinit(self: Column, alloc: std.mem.Allocator) void {
        if (self.formatted) |fields| {
            for (fields) |formatted| alloc.free(formatted);
            alloc.free(fields);
        }
    }

    //
    // accessors
    //

    // Return one rendered or raw cell by visible row index.
    pub fn field(self: Column, index: usize) Field {
        if (self.formatted) |fields| return fields[index];
        return self.table.row(index)[self.index];
    }

    //
    // measure/infer
    //

    // Measure the widest visible cell in this column.
    fn measure(self: Column) usize {
        var width = doomicode.displayWidth(self.name);
        for (0..self.table.nrows()) |index| {
            width = @max(width, doomicode.displayWidth(self.field(index)));
        }
        return width;
    }

    // Infer the display type for the visible cells in this column.
    fn inferColumnType(self: Column) ColumnType {
        var floats: bool = false;
        var ints: bool = false;

        for (0..self.table.nrows()) |visible_row| {
            const value = self.table.row(visible_row)[self.index];
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

    // Format visible numeric cells into owned display strings.
    fn formatColumn(
        self: *Column,
        comptime formatter: fn (*Column, std.mem.Allocator, []const u8) anyerror![]u8,
    ) !void {
        const alloc = self.table.alloc;
        const fields = try alloc.alloc(Field, self.table.nrows());
        errdefer alloc.free(fields);

        var ii: usize = 0;
        errdefer {
            for (fields[0..ii]) |formatted| alloc.free(formatted);
        }
        for (0..self.table.nrows()) |visible_row| {
            fields[ii] = try formatter(self, alloc, self.table.row(visible_row)[self.index]);
            ii += 1;
        }
        self.formatted = fields;
    }

    // Format one integer cell for display.
    fn formatInt(self: *Column, alloc: std.mem.Allocator, raw: []const u8) ![]u8 {
        _ = self;
        return int.intFormat(alloc, raw);
    }

    // Format one floating-point cell for display.
    fn formatFloat(self: *Column, alloc: std.mem.Allocator, raw: []const u8) ![]u8 {
        return float.floatFormat(alloc, raw, self.table.config.digits);
    }
};

// Display-oriented type inferred for a column.
pub const ColumnType = enum { int, float, string };

//
// testing
//

test "column init stores table header and index" {
    const table = try Table.initCsv(testing.allocator, .{}, "a,b\nc,d\n");
    defer table.deinit();

    const column = table.column(1);
    try testing.expectEqual(table, column.table);
    try testing.expectEqualStrings("b", column.name);
    try testing.expectEqual(@as(usize, 1), column.index);
    try testing.expectEqual(@as(usize, 1), column.width);
    try testing.expectEqual(ColumnType.string, column.type);
}

test "column tail formatting and width use visible rows" {
    const table = try Table.initCsv(testing.allocator, .{ .tail = 1 }, "a,b\nsuper-wide,1\nok,2\n");
    defer table.deinit();

    try testing.expectEqualStrings("ok", table.column(0).field(0));
    try testing.expectEqual(@as(usize, 2), table.column(0).width);
    try testing.expectEqualStrings("2", table.column(1).field(0));
}

test "column formatting and inference cases" {
    const cases = [_]struct {
        name: []const u8,
        config: types.Config = .{},
        input: []const u8,
        index: usize,
        want_type: ColumnType,
        want_width: usize,
        want_fields: []const []const u8,
    }{
        .{ .name = "vanilla", .config = .{ .vanilla = true }, .input = "a\n1234\n", .index = 0, .want_type = .string, .want_width = 4, .want_fields = &.{"1234"} },
        .{ .name = "widest", .input = "alpha,b\nx,longer\n", .index = 1, .want_type = .string, .want_width = 6, .want_fields = &.{"longer"} },
        .{ .name = "int width", .input = "a\n1234\n", .index = 0, .want_type = .int, .want_width = 5, .want_fields = &.{"1,234"} },
        .{ .name = "float width", .input = "a\n1234.0\n", .index = 0, .want_type = .float, .want_width = 9, .want_fields = &.{"1,234.000"} },
        .{ .name = "float digits", .config = .{ .digits = 2 }, .input = "a\n12.34567\n", .index = 0, .want_type = .float, .want_width = 5, .want_fields = &.{"12.34"} },
        .{ .name = "float blanks", .input = "a,b\n64,\n61.5,\n,\n", .index = 0, .want_type = .float, .want_width = 6, .want_fields = &.{ "64.000", "61.500", "" } },
        .{ .name = "infer int", .input = "a,b,c\n1,12.5,foo\n22,3.0,barbaz\n", .index = 0, .want_type = .int, .want_width = 2, .want_fields = &.{ "1", "22" } },
        .{ .name = "infer float", .input = "a,b,c\n1,12.5,foo\n22,3.0,barbaz\n", .index = 1, .want_type = .float, .want_width = 6, .want_fields = &.{ "12.500", "3.000" } },
        .{ .name = "infer string", .input = "a,b,c\n1,12.5,foo\n22,3.0,barbaz\n", .index = 2, .want_type = .string, .want_width = 6, .want_fields = &.{ "foo", "barbaz" } },
    };

    for (cases) |tc| {
        const table = try Table.initCsv(testing.allocator, tc.config, tc.input);
        defer table.deinit();
        const col = table.column(tc.index);
        try testing.expectEqual(tc.want_type, col.type);
        try testing.expectEqual(tc.want_width, col.width);
        for (tc.want_fields, 0..) |want, ii| try testing.expectEqualStrings(want, col.field(ii));
    }
}

test "column inference ignores blanks and scans all rows" {
    var buf = std.ArrayList(u8).empty;
    defer buf.deinit(testing.allocator);

    try buf.appendSlice(testing.allocator, "a,b\n");
    for (0..100) |ii| {
        try buf.writer(testing.allocator).print("{d},\n", .{ii});
    }
    try buf.appendSlice(testing.allocator, "not-a-number,\n");

    const table = try Table.initCsv(testing.allocator, .{}, buf.items);
    defer table.deinit();

    try testing.expectEqual(ColumnType.string, table.column(0).type);
    try testing.expectEqual(ColumnType.string, table.column(1).type);
}

const doomicode = @import("doomicode.zig");
const Field = @import("types.zig").Field;
const float = @import("float.zig");
const int = @import("int.zig");
const std = @import("std");
const testing = std.testing;
const Table = @import("table.zig").Table;
const types = @import("types.zig");
