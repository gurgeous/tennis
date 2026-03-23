// Parsed table data plus rendering-time caches and helpers.
pub const Table = struct {
    alloc: std.mem.Allocator,
    data: Data,
    columns: []Column,
    config: types.Config = .{},
    empty: bool = false,
    col_order: []usize,
    header_row: Row,
    row_order: []usize,
    visible_row_count: usize = 0,
    // memoized
    _style: ?Style = null,
    _term_width: ?usize = null,

    const Self = @This();

    //
    // init/deinit
    //

    // Build a table from pre-parsed stored rows.
    pub fn init(alloc: std.mem.Allocator, config: types.Config, data: Data) !*Table {
        const table = try alloc.create(Table);
        errdefer alloc.destroy(table);

        const col_order = try alloc.alloc(usize, if (data.rows.len > 1) data.headers().len else 0);
        errdefer alloc.free(col_order);
        const row_order = try alloc.alloc(usize, if (data.rows.len > 0) data.rows.len - 1 else 0);
        errdefer alloc.free(row_order);

        table.* = .{
            .alloc = alloc,
            .columns = &.{},
            .col_order = col_order,
            .config = config,
            .data = data,
            .header_row = &.{},
            .row_order = row_order,
        };

        // Input with zero data rows is intentionally rendered as "empty".
        table.empty = data.rows.len < 2;

        if (!table.empty) {
            for (table.col_order, 0..) |*slot, ii| slot.* = ii;
            if (config.select.len > 0) try table.selectCols();
            table.header_row = try table.buildHeaderRow();
            errdefer alloc.free(table.header_row);

            for (table.row_order, 0..) |*slot, ii| slot.* = ii;
            if (config.sort.len > 0) try table.sortRows();
            if (config.reverse) std.mem.reverse(usize, table.row_order);

            var n: usize = table.nrows();
            if (config.head > 0) n = @min(config.head, n);
            if (config.tail > 0) n = @min(config.tail, n);
            table.visible_row_count = n;
        }

        var timer = try std.time.Timer.start();
        table.columns = try table.buildColumns();
        util.benchmark(" table.columns", timer.read());
        return table;
    }

    // This is just for testing at the moment
    pub fn initCsv(alloc: std.mem.Allocator, config: types.Config, bytes: []const u8) !*Table {
        const data = try csv.load(alloc, bytes, config.delimiter);
        errdefer data.deinit(alloc);
        return init(alloc, config, data);
    }

    // Release the table, columns, style cache, and stored rows.
    pub fn deinit(self: *Self) void {
        for (self.columns) |col| col.deinit(self.alloc);
        self.alloc.free(self.columns);
        if (!self.empty) self.alloc.free(self.header_row);
        self.alloc.free(self.col_order);
        self.alloc.free(self.row_order);
        self.data.deinit(self.alloc);
        self.alloc.destroy(self);
    }

    //
    // main
    //

    // Render this table to the provided writer.
    pub fn renderTable(self: *Self, writer: *std.Io.Writer) !void {
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

    // Report whether the table has no data rows.
    pub fn isEmpty(self: *const Self) bool {
        return self.empty;
    }

    // Return the header row.
    pub fn headers(self: *const Self) Row {
        if (self.empty) return &.{};
        return self.header_row;
    }

    // Return the number of loaded data rows.
    pub fn nrows(self: *const Self) usize {
        if (self.empty) return 0;
        return self.data.rows.len - 1;
    }

    // note: does not include row-number column
    // Return the number of columns in the table.
    pub fn ncols(self: *const Self) usize {
        return self.col_order.len;
    }

    // Return one loaded data row.
    pub fn row(self: *const Self, index: usize) Row {
        return self.data.row(self.row_order[index] + 1);
    }

    // Return the number of visible rows after head/tail clipping.
    pub fn visibleRowCount(self: *const Self) usize {
        return self.visible_row_count;
    }

    // Map a visible row index back to the loaded row index.
    pub fn visibleRow(self: *const Self, index: usize) usize {
        const n = self.nrows();
        if (self.config.tail > 0) return n - self.visibleRowCount() + index;
        return index;
    }

    // Return the last visible 1-based row number for row-number layout.
    pub fn visibleLastRowNumber(self: *const Self) usize {
        const count = self.visibleRowCount();
        if (count == 0) return 0; // REVIEW: should we check empty here?
        return self.visibleRow(count - 1) + 1;
    }

    // Return one built column view.
    pub fn column(self: *const Self, index: usize) Column {
        return self.columns[index];
    }

    //
    // memoized accessors
    //

    // Return the cached style, building it on first use.
    pub fn style(self: *Self) *const Style {
        if (self._style == null) {
            self._style = Style.init(self.alloc, self.config.color, self.config.theme);
        }
        return &self._style.?;
    }

    // Return the detected terminal width, caching the first probe.
    pub fn termWidth(self: *Self) usize {
        if (self._term_width == null) {
            self._term_width = if (self.config.width > 0) self.config.width else util.termWidth();
        }
        return self._term_width.?;
    }

    // Build every column for this table.
    fn buildColumns(self: *const Self) ![]Column {
        const columns = try self.alloc.alloc(Column, self.ncols());
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

    fn sortRows(self: *Self) !void {
        if (self.config.sort.len > 0) {
            const sorter = try sort.Sort.init(self.alloc, self.data.headers(), self.config.sort);
            defer sorter.deinit(self.alloc);
            sorter.apply(self.data, self.row_order);
        }
    }

    // Return the source column index for one visible column.
    pub fn sourceCol(self: *const Self, index: usize) usize {
        return self.col_order[index];
    }

    // Resolve selected visible columns against the source header row.
    fn selectCols(self: *Self) !void {
        var select = try sort.Select.init(self.alloc, self.data.headers(), self.config.select);
        self.alloc.free(self.col_order);
        self.col_order = select.cols;
        select.cols = &.{};
    }

    // Build the visible header row in selected display order.
    fn buildHeaderRow(self: *const Self) !Row {
        const out = try self.alloc.alloc(Field, self.col_order.len);
        for (self.col_order, 0..) |col, ii| out[ii] = self.data.headers()[col];
        return out;
    }
};

//
// testing
//

test "table shape and headers" {
    const cases = [_]struct {
        name: []const u8,
        config: types.Config = .{},
        input: []const u8,
        headers: []const []const u8,
        nrows: usize,
        ncols: usize,
        empty: bool,
        first_row: ?[]const []const u8 = null,
    }{
        .{ .name = "basic", .input = "a,b\nc,d\n", .headers = &.{ "a", "b" }, .nrows = 1, .ncols = 2, .empty = false, .first_row = &.{ "c", "d" } },
        .{ .name = "empty", .input = "", .headers = &.{}, .nrows = 0, .ncols = 0, .empty = true },
        .{ .name = "header only", .input = "a,b\n", .headers = &.{}, .nrows = 0, .ncols = 0, .empty = true },
        .{ .name = "semicolon", .config = .{ .delimiter = ';' }, .input = "a;b\nc;d\n", .headers = &.{ "a", "b" }, .nrows = 1, .ncols = 2, .empty = false, .first_row = &.{ "c", "d" } },
    };

    for (cases) |tc| {
        const table = try Table.initCsv(testing.allocator, tc.config, tc.input);
        defer table.deinit();

        try test_support.expectStrings(tc.headers, table.headers());
        try testing.expectEqual(tc.nrows, table.nrows());
        try testing.expectEqual(tc.ncols, table.ncols());
        try testing.expectEqual(tc.empty, table.isEmpty());
        if (tc.first_row) |row| try test_support.expectStrings(row, table.row(0));
        if (tc.empty and tc.input.len > 0) try testing.expectEqual(@as(usize, 0), table.columns.len);
    }
}

test "row returns data rows only" {
    const table = try Table.initCsv(testing.allocator, .{}, "a,b\nc,d\ne,f\n");
    defer table.deinit();

    const row1 = table.row(0);
    try testing.expectEqualStrings("c", row1[0]);
    try testing.expectEqualStrings("d", row1[1]);

    const row2 = table.row(1);
    try testing.expectEqualStrings("e", row2[0]);
    try testing.expectEqualStrings("f", row2[1]);
}

test "visible rows support head and tail" {
    const cases = [_]struct {
        config: types.Config,
        want_count: usize,
        rows: []const usize,
    }{
        .{ .config = .{ .head = 2 }, .want_count = 2, .rows = &.{ 0, 1 } },
        .{ .config = .{ .tail = 2 }, .want_count = 2, .rows = &.{ 1, 2 } },
    };

    for (cases) |tc| {
        const table = try Table.initCsv(testing.allocator, tc.config, "a,b\n1,2\n3,4\n5,6\n");
        defer table.deinit();

        try testing.expectEqual(tc.want_count, table.visibleRowCount());
        for (tc.rows, 0..) |want, ii| try testing.expectEqual(want, table.visibleRow(ii));
    }
}

test "table sorts rows by one column" {
    const table = try Table.initCsv(testing.allocator, .{ .sort = "name" }, "name,score\nbob,2\nalice,1\ncara,3\n");
    defer table.deinit();

    try test_support.expectStrings(&.{ "alice", "1" }, table.row(0));
    try test_support.expectStrings(&.{ "bob", "2" }, table.row(1));
    try test_support.expectStrings(&.{ "cara", "3" }, table.row(2));
}

test "table sorts rows by multiple columns" {
    const table = try Table.initCsv(testing.allocator, .{ .sort = "city,name" }, "name,city\nbob,denver\ncara,boston\nalice,boston\n");
    defer table.deinit();

    try test_support.expectStrings(&.{ "alice", "boston" }, table.row(0));
    try test_support.expectStrings(&.{ "cara", "boston" }, table.row(1));
    try test_support.expectStrings(&.{ "bob", "denver" }, table.row(2));
}

test "table sorts with case insensitive header match" {
    const table = try Table.initCsv(testing.allocator, .{ .sort = "NAME" }, "name,score\nbob,2\nalice,1\n");
    defer table.deinit();

    try test_support.expectStrings(&.{ "alice", "1" }, table.row(0));
    try test_support.expectStrings(&.{ "bob", "2" }, table.row(1));
}

test "table selects a subset of columns" {
    const table = try Table.initCsv(testing.allocator, .{ .select = "score,name" }, "name,score,city\nbob,2,denver\nalice,1,boston\n");
    defer table.deinit();

    try test_support.expectStrings(&.{ "score", "name" }, table.headers());
    try testing.expectEqual(@as(usize, 2), table.ncols());
    try testing.expectEqualStrings("2", table.column(0).field(0));
    try testing.expectEqualStrings("bob", table.column(1).field(0));
    try testing.expectEqualStrings("1", table.column(0).field(1));
    try testing.expectEqualStrings("alice", table.column(1).field(1));
}

test "table select supports duplicates" {
    const table = try Table.initCsv(testing.allocator, .{ .select = "name,score,name" }, "name,score\nbob,2\n");
    defer table.deinit();

    try test_support.expectStrings(&.{ "name", "score", "name" }, table.headers());
    try testing.expectEqual(@as(usize, 3), table.ncols());
    try testing.expectEqualStrings("bob", table.column(0).field(0));
    try testing.expectEqualStrings("2", table.column(1).field(0));
    try testing.expectEqualStrings("bob", table.column(2).field(0));
}

test "table sorts using hidden columns after select" {
    const table = try Table.initCsv(testing.allocator, .{ .select = "name", .sort = "score" }, "name,score\nbob,2\nalice,1\n");
    defer table.deinit();

    try test_support.expectStrings(&.{"name"}, table.headers());
    try testing.expectEqual(@as(usize, 1), table.ncols());
    try testing.expectEqualStrings("alice", table.column(0).field(0));
    try testing.expectEqualStrings("bob", table.column(0).field(1));
}

test "table sorts before head and tail" {
    const head = try Table.initCsv(testing.allocator, .{ .sort = "name", .head = 2 }, "name,score\ncara,3\nbob,2\nalice,1\n");
    defer head.deinit();
    try testing.expectEqual(@as(usize, 2), head.visibleRowCount());
    try test_support.expectStrings(&.{ "alice", "1" }, head.row(head.visibleRow(0)));
    try test_support.expectStrings(&.{ "bob", "2" }, head.row(head.visibleRow(1)));

    const tail = try Table.initCsv(testing.allocator, .{ .sort = "name", .tail = 2 }, "name,score\ncara,3\nbob,2\nalice,1\n");
    defer tail.deinit();
    try testing.expectEqual(@as(usize, 2), tail.visibleRowCount());
    try test_support.expectStrings(&.{ "bob", "2" }, tail.row(tail.visibleRow(0)));
    try test_support.expectStrings(&.{ "cara", "3" }, tail.row(tail.visibleRow(1)));
}

test "table reverses rows before head and tail" {
    const head = try Table.initCsv(testing.allocator, .{ .reverse = true, .head = 2 }, "name,score\nalice,1\nbob,2\ncara,3\n");
    defer head.deinit();
    try testing.expectEqual(@as(usize, 2), head.visibleRowCount());
    try test_support.expectStrings(&.{ "cara", "3" }, head.row(head.visibleRow(0)));
    try test_support.expectStrings(&.{ "bob", "2" }, head.row(head.visibleRow(1)));

    const tail = try Table.initCsv(testing.allocator, .{ .reverse = true, .tail = 2 }, "name,score\nalice,1\nbob,2\ncara,3\n");
    defer tail.deinit();
    try testing.expectEqual(@as(usize, 2), tail.visibleRowCount());
    try test_support.expectStrings(&.{ "bob", "2" }, tail.row(tail.visibleRow(0)));
    try test_support.expectStrings(&.{ "alice", "1" }, tail.row(tail.visibleRow(1)));
}

test "table reverses sorted rows" {
    const table = try Table.initCsv(testing.allocator, .{ .sort = "name", .reverse = true }, "name,score\nbob,2\nalice,1\ncara,3\n");
    defer table.deinit();

    try test_support.expectStrings(&.{ "cara", "3" }, table.row(0));
    try test_support.expectStrings(&.{ "bob", "2" }, table.row(1));
    try test_support.expectStrings(&.{ "alice", "1" }, table.row(2));
}

test "visible rows clamp oversized head and tail" {
    const head = try Table.initCsv(testing.allocator, .{ .head = 100 }, "a,b\n1,2\n3,4\n");
    defer head.deinit();
    try testing.expectEqual(@as(usize, 2), head.visibleRowCount());
    try testing.expectEqual(@as(usize, 2), head.visibleLastRowNumber());

    const tail = try Table.initCsv(testing.allocator, .{ .tail = 100 }, "a,b\n1,2\n3,4\n");
    defer tail.deinit();
    try testing.expectEqual(@as(usize, 2), tail.visibleRowCount());
    try testing.expectEqual(@as(usize, 2), tail.visibleLastRowNumber());
}

test "table builds columns from headers" {
    const table = try Table.initCsv(testing.allocator, .{}, "a,b\nc,d\ne,f\n");
    defer table.deinit();

    try testing.expectEqual(@as(usize, 2), table.columns.len);
    try testing.expectEqualStrings("a", table.columns[0].name);
    try testing.expectEqualStrings("b", table.columns[1].name);
}

test "style respects config" {
    const table1 = try Table.initCsv(testing.allocator, .{ .color = .off, .theme = .dark }, "a,b\nc,d\n");
    defer table1.deinit();
    try testing.expectEqualStrings("", table1.style().title);
    try testing.expectEqualStrings("", table1.style().chrome);

    const table2 = try Table.initCsv(testing.allocator, .{ .color = .on, .theme = .dark }, "a,b\nc,d\n");
    defer table2.deinit();
    try testing.expect(table2.style().title.len > 0);
    try testing.expect(table2.style().chrome.len > 0);
}

test "termWidth respects config width" {
    const table = try Table.initCsv(testing.allocator, .{ .width = 123 }, "a,b\nc,d\n");
    defer table.deinit();

    try testing.expectEqual(@as(usize, 123), table.termWidth());
}

const Column = @import("column.zig").Column;
const csv = @import("csv.zig");
const Data = @import("data.zig").Data;
const Field = @import("types.zig").Field;
const Layout = @import("layout.zig").Layout;
const Render = @import("render.zig").Render;
const Row = @import("types.zig").Row;
const sort = @import("sort.zig");
const std = @import("std");
const Style = @import("style.zig").Style;
const testing = std.testing;
const test_support = @import("test_support.zig");
const types = @import("types.zig");
const util = @import("util.zig");
