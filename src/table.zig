pub const Table = struct {
    // passed into init
    alloc: std.mem.Allocator,
    csv: Csv,
    columns: []Column,
    config: types.Config = .{},
    empty: bool = false,
    // calculated from config + terminal
    style_cache: ?Style = null,
    term_width: ?usize = null,

    //
    // init/deinit
    //

    pub fn init(alloc: std.mem.Allocator, config: types.Config, reader: anytype) !*Table {
        const table = try alloc.create(Table);
        errdefer alloc.destroy(table);

        const csv = try Csv.init(alloc, reader, .{
            .delimiter = config.delimiter,
            .max_rows = if (config.head > 0 and config.tail == 0) config.head + 1 else 0,
        });
        errdefer csv.deinit(alloc);

        // A csv with zero data rows is intentionally rendered as "empty"
        const empty = csv.rows.len < 2;

        table.* = .{
            .alloc = alloc,
            .columns = &.{},
            .config = config,
            .csv = csv,
            .empty = empty,
        };
        var timer = try std.time.Timer.start();
        table.columns = try table.buildColumns();
        util.benchmark(" table.columns", timer.read());
        return table;
    }

    pub fn deinit(self: *Table) void {
        for (self.columns) |col| col.deinit(self.alloc);
        self.alloc.free(self.columns);
        self.csv.deinit(self.alloc);
        self.alloc.destroy(self);
    }

    //
    // main
    //

    pub fn renderTable(self: *Table, writer: *std.Io.Writer) !void {
        var timer = try std.time.Timer.start();
        const layout = try Layout.init(self);
        defer layout.deinit(self.alloc);
        util.benchmark(" render.layout", timer.read());

        var renderer: Render = .init(self, writer, layout);
        defer renderer.deinit();
        timer = try std.time.Timer.start();
        try renderer.render();
        util.benchmark(" render.output", timer.read());
    }

    //
    // accessors
    //

    pub fn isEmpty(self: *const Table) bool {
        return self.empty;
    }

    pub fn headers(self: *const Table) Row {
        if (self.empty) return &.{};
        return self.csv.rows[0];
    }

    pub fn nrows(self: *const Table) usize {
        if (self.empty) return 0;
        return self.csv.rows.len - 1;
    }

    // note: does not include row-number column
    pub fn ncols(self: *const Table) usize {
        return self.columns.len;
    }

    pub fn rows(self: *const Table) Rows {
        if (self.empty) return &.{};
        return self.csv.rows[1..];
    }

    pub fn visibleRowCount(self: *const Table) usize {
        const n = self.nrows();
        if (n == 0) return 0;
        if (self.config.head > 0) return @min(self.config.head, n);
        if (self.config.tail > 0) return @min(self.config.tail, n);
        return n;
    }

    pub fn visibleRow(self: *const Table, index: usize) usize {
        const n = self.nrows();
        if (self.config.tail > 0) return n - self.visibleRowCount() + index;
        return index;
    }

    pub fn column(self: *const Table, index: usize) Column {
        return self.columns[index];
    }

    //
    // memoized accessors
    //

    pub fn style(self: *Table) *const Style {
        if (self.style_cache == null) {
            self.style_cache = Style.init(self.alloc, self.config.color, self.config.theme);
        }
        return &self.style_cache.?;
    }

    pub fn termWidth(self: *Table) usize {
        if (self.term_width == null) {
            self.term_width = if (self.config.width > 0) self.config.width else util.termWidth();
        }
        return self.term_width.?;
    }

    fn buildColumns(self: *const Table) ![]Column {
        const columns = try self.alloc.alloc(Column, self.headers().len);
        errdefer self.alloc.free(columns);

        var ii: usize = 0;
        errdefer {
            for (columns[0..ii]) |col| col.deinit(self.alloc);
        }
        for (columns, 0..) |*col, index| {
            col.* = try Column.init(self, index);
            ii += 1;
        }
        return columns;
    }
};

test "headers length and emptiness reflect table shape" {
    var in = std.io.fixedBufferStream("a,b\nc,d\n");
    const table = try Table.init(std.testing.allocator, .{}, in.reader());
    defer table.deinit();

    try std.testing.expectEqual(@as(usize, 2), table.headers().len);
    try std.testing.expectEqualStrings("a", table.headers()[0]);
    try std.testing.expectEqualStrings("b", table.headers()[1]);
    try std.testing.expectEqual(@as(usize, 1), table.nrows());
    try std.testing.expectEqual(@as(usize, 2), table.ncols());
    try std.testing.expect(!table.isEmpty());
}

test "empty input reports empty table" {
    var in = std.io.fixedBufferStream("");
    const table = try Table.init(std.testing.allocator, .{}, in.reader());
    defer table.deinit();

    try std.testing.expectEqual(@as(usize, 0), table.headers().len);
    try std.testing.expectEqual(@as(usize, 0), table.nrows());
    try std.testing.expectEqual(@as(usize, 0), table.ncols());
    try std.testing.expect(table.isEmpty());
}

test "header only input is empty" {
    var in = std.io.fixedBufferStream("a,b\n");
    const table = try Table.init(std.testing.allocator, .{}, in.reader());
    defer table.deinit();

    try std.testing.expect(table.isEmpty());
    try std.testing.expectEqual(@as(usize, 0), table.headers().len);
    try std.testing.expectEqual(@as(usize, 0), table.nrows());
    try std.testing.expectEqual(@as(usize, 0), table.columns.len);
}

test "table with semicolon delimiter" {
    var in = std.io.fixedBufferStream("a;b\nc;d\n");
    const table = try Table.init(std.testing.allocator, .{ .delimiter = ';' }, in.reader());
    defer table.deinit();

    try std.testing.expectEqual(@as(usize, 2), table.headers().len);
    try std.testing.expectEqualStrings("a", table.headers()[0]);
    try std.testing.expectEqualStrings("b", table.headers()[1]);
    try std.testing.expectEqual(@as(usize, 1), table.nrows());
    try std.testing.expectEqualStrings("c", table.rows()[0][0]);
    try std.testing.expectEqualStrings("d", table.rows()[0][1]);
}

test "rows returns data rows only" {
    var in = std.io.fixedBufferStream("a,b\nc,d\ne,f\n");
    const table = try Table.init(std.testing.allocator, .{}, in.reader());
    defer table.deinit();

    const rows = table.rows();
    try std.testing.expectEqual(@as(usize, 2), rows.len);

    const row1 = rows[0];
    try std.testing.expectEqualStrings("c", row1[0]);
    try std.testing.expectEqualStrings("d", row1[1]);

    const row2 = rows[1];
    try std.testing.expectEqualStrings("e", row2[0]);
    try std.testing.expectEqualStrings("f", row2[1]);
}

test "visible rows supports head" {
    var in = std.io.fixedBufferStream("a,b\n1,2\n3,4\n5,6\n");
    const table = try Table.init(std.testing.allocator, .{ .head = 2 }, in.reader());
    defer table.deinit();

    try std.testing.expectEqual(@as(usize, 2), table.visibleRowCount());
    try std.testing.expectEqual(@as(usize, 0), table.visibleRow(0));
    try std.testing.expectEqual(@as(usize, 1), table.visibleRow(1));
}

test "visible rows supports tail" {
    var in = std.io.fixedBufferStream("a,b\n1,2\n3,4\n5,6\n");
    const table = try Table.init(std.testing.allocator, .{ .tail = 2 }, in.reader());
    defer table.deinit();

    try std.testing.expectEqual(@as(usize, 2), table.visibleRowCount());
    try std.testing.expectEqual(@as(usize, 1), table.visibleRow(0));
    try std.testing.expectEqual(@as(usize, 2), table.visibleRow(1));
}

test "table builds columns from headers" {
    var in = std.io.fixedBufferStream("a,b\nc,d\ne,f\n");
    const table = try Table.init(std.testing.allocator, .{}, in.reader());
    defer table.deinit();

    try std.testing.expectEqual(@as(usize, 2), table.columns.len);
    try std.testing.expectEqualStrings("a", table.columns[0].name);
    try std.testing.expectEqualStrings("b", table.columns[1].name);
}

test "style respects config" {
    var in = std.io.fixedBufferStream("a,b\nc,d\n");
    const table1 = try Table.init(std.testing.allocator, .{ .color = .off, .theme = .dark }, in.reader());
    defer table1.deinit();
    try std.testing.expectEqualStrings("", table1.style().title);
    try std.testing.expectEqualStrings("", table1.style().chrome);

    var in2 = std.io.fixedBufferStream("a,b\nc,d\n");
    const table2 = try Table.init(std.testing.allocator, .{ .color = .on, .theme = .dark }, in2.reader());
    defer table2.deinit();
    try std.testing.expect(table2.style().title.len > 0);
    try std.testing.expect(table2.style().chrome.len > 0);
}

test "termWidth respects config width" {
    var in = std.io.fixedBufferStream("a,b\nc,d\n");
    const table = try Table.init(std.testing.allocator, .{ .width = 123 }, in.reader());
    defer table.deinit();

    try std.testing.expectEqual(@as(usize, 123), table.termWidth());
}

const Column = @import("column.zig").Column;
const Csv = @import("csv.zig").Csv;
const Layout = @import("layout.zig").Layout;
const Render = @import("render.zig").Render;
const Row = @import("types.zig").Row;
const Rows = @import("types.zig").Rows;
const std = @import("std");
const Style = @import("style.zig").Style;
const types = @import("types.zig");
const util = @import("util.zig");
