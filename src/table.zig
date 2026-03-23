// Parsed table data plus rendering-time caches and helpers.
pub const Table = struct {
    alloc: std.mem.Allocator,
    data: Data,
    columns: []Column,
    config: types.Config = .{},
    empty: bool = false,
    col_view: []usize,
    row_view: []usize,
    row_count: usize = 0,
    visible_row_count: usize = 0,
    // memoized
    _headers: ?Row = null,
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

        const col_view = try alloc.alloc(usize, if (data.rows.len > 1) data.headers().len else 0);
        errdefer alloc.free(col_view);
        const row_view = try alloc.alloc(usize, if (data.rows.len > 0) data.rows.len - 1 else 0);
        errdefer alloc.free(row_view);

        const empty = data.rows.len < 2;
        table.* = .{
            .alloc = alloc,
            .columns = &.{},
            .col_view = col_view,
            .config = config,
            .data = data,
            .empty = empty,
            .row_count = row_view.len,
            .row_view = row_view,
        };

        var timer = try std.time.Timer.start();
        if (!table.empty) try table.transforms();
        util.benchmark(" table.transforms", timer.read());

        timer = try std.time.Timer.start();
        table.columns = try table.buildColumns();
        util.benchmark(" table.columns", timer.read());
        return table;
    }

    // This is just for testing at the moment
    pub fn initCsv(alloc: std.mem.Allocator, config: types.Config, bytes: []const u8) !*Table {
        const data = try csv.load(alloc, bytes, config.delimiter);
        errdefer data.deinit(alloc);
        var bound = config;
        defer bound.deinit(alloc);
        try bound.bind(alloc, data.headers());
        return init(alloc, bound, data);
    }

    // Release the table, columns, style cache, and stored rows.
    pub fn deinit(self: *Self) void {
        for (self.columns) |col| col.deinit(self.alloc);
        self.alloc.free(self.columns);
        if (self._headers) |cached| self.alloc.free(cached);
        self.alloc.free(self.col_view);
        self.alloc.free(self.row_view);
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
    pub fn headers(self: *Self) Row {
        if (self.empty) return &.{};
        if (self._headers == null) self._headers = self.buildHeaders() catch unreachable;
        return self._headers.?;
    }

    // Return the number of visible rows after clipping.
    pub fn nrows(self: *const Self) usize {
        return self.visible_row_count;
    }

    // note: does not include row-number column
    // Return the number of columns in the table.
    pub fn ncols(self: *const Self) usize {
        return self.col_view.len;
    }

    // Return one visible data row.
    pub fn row(self: *const Self, visible_index: usize) Row {
        return self.data.row(self.row_view[self.sourceRow(visible_index)] + 1);
    }

    // Return one built column view.
    pub fn column(self: *const Self, visible_index: usize) Column {
        return self.columns[visible_index];
    }

    // Return one source row index for one visible row.
    pub fn sourceRow(self: *const Self, visible_index: usize) usize {
        if (self.config.tail > 0) return self.row_view.len - self.visible_row_count + visible_index;
        return visible_index;
    }

    // Return the source column index for one visible column.
    pub fn sourceCol(self: *const Self, visible_index: usize) usize {
        return self.col_view[visible_index];
    }

    // Return the last visible 1-based row number for row-number layout.
    pub fn lastRowNumber(self: *const Self) usize {
        if (self.empty) return 0;
        return self.sourceRow(self.nrows() - 1) + 1;
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

    // Build the visible header row in selected display order.
    fn buildHeaders(self: *const Self) !Row {
        const out = try self.alloc.alloc(Field, self.col_view.len);
        for (self.col_view, 0..) |col, ii| out[ii] = self.data.headers()[col];
        return out;
    }

    // Build every column for this table.
    fn buildColumns(self: *Self) ![]Column {
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

    // Apply display transforms such as select, filter, sort, and clipping.
    fn transforms(self: *Self) !void {
        // --select
        for (self.col_view, 0..) |*slot, ii| slot.* = ii;
        if (self.config.select_cols.len > 0) {
            const out = self.alloc.dupe(usize, self.config.select_cols) catch unreachable;
            self.alloc.free(self.col_view);
            self.col_view = out;
        }

        // --filter, --sort, --shuffle, --reverse
        for (self.row_view, 0..) |*slot, ii| slot.* = ii;
        if (self.config.filter.len > 0) self.filterRows();
        if (self.config.sort_cols.len > 0) {
            const sorter: sort.Sort = .{ .cols = self.config.sort_cols };
            sorter.apply(self.data, self.row_view);
        }
        if (self.config.shuffle) {
            const seed = if (self.config.srand != 0) self.config.srand else std.crypto.random.int(u64);
            var prng = std.Random.DefaultPrng.init(seed);
            prng.random().shuffle(usize, self.row_view);
        }
        if (self.config.reverse) std.mem.reverse(usize, self.row_view);

        // set visible_row_count
        var n: usize = self.row_count;
        if (self.config.head > 0) n = @min(self.config.head, n);
        if (self.config.tail > 0) n = @min(self.config.tail, n);
        self.visible_row_count = n;
    }

    // Keep only rows where any field contains the case-insensitive filter text.
    fn filterRows(self: *Self) void {
        var out: usize = 0;
        for (self.row_view) |row_index| {
            const data_row = self.data.row(row_index + 1);
            for (data_row) |field| {
                if (util.containsIgnoreCase(field, self.config.filter)) {
                    self.row_view[out] = row_index;
                    out += 1;
                    break;
                }
            }
        }
        self.row_count = out;
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

test "nrows and row reflect head and tail" {
    const cases = [_]struct {
        config: types.Config,
        want_count: usize,
        rows: []const []const []const u8,
    }{
        .{ .config = .{ .head = 2 }, .want_count = 2, .rows = &.{ &.{ "1", "2" }, &.{ "3", "4" } } },
        .{ .config = .{ .tail = 2 }, .want_count = 2, .rows = &.{ &.{ "3", "4" }, &.{ "5", "6" } } },
    };

    for (cases) |tc| {
        const table = try Table.initCsv(testing.allocator, tc.config, "a,b\n1,2\n3,4\n5,6\n");
        defer table.deinit();

        try testing.expectEqual(tc.want_count, table.nrows());
        for (tc.rows, 0..) |want, ii| try test_support.expectStrings(want, table.row(ii));
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

test "table filters rows by case insensitive substring" {
    const table = try Table.initCsv(testing.allocator, .{ .filter = "ali" }, "name,score,city\nbob,2,denver\nAlice,1,boston\nmali,3,paris\n");
    defer table.deinit();

    try testing.expectEqual(@as(usize, 2), table.nrows());
    try test_support.expectStrings(&.{ "Alice", "1", "boston" }, table.row(0));
    try test_support.expectStrings(&.{ "mali", "3", "paris" }, table.row(1));
}

test "table filters before sort and head" {
    const table = try Table.initCsv(testing.allocator, .{ .filter = "bo", .sort = "score", .head = 1 }, "name,score,city\nbob,2,denver\nAlice,1,boston\nmali,3,paris\nboris,4,rome\n");
    defer table.deinit();

    try testing.expectEqual(@as(usize, 1), table.nrows());
    try test_support.expectStrings(&.{ "Alice", "1", "boston" }, table.row(0));
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
    try testing.expectEqual(@as(usize, 2), head.nrows());
    try test_support.expectStrings(&.{ "alice", "1" }, head.row(0));
    try test_support.expectStrings(&.{ "bob", "2" }, head.row(1));

    const tail = try Table.initCsv(testing.allocator, .{ .sort = "name", .tail = 2 }, "name,score\ncara,3\nbob,2\nalice,1\n");
    defer tail.deinit();
    try testing.expectEqual(@as(usize, 2), tail.nrows());
    try test_support.expectStrings(&.{ "bob", "2" }, tail.row(0));
    try test_support.expectStrings(&.{ "cara", "3" }, tail.row(1));
}

test "table reverses rows before head and tail" {
    const head = try Table.initCsv(testing.allocator, .{ .reverse = true, .head = 2 }, "name,score\nalice,1\nbob,2\ncara,3\n");
    defer head.deinit();
    try testing.expectEqual(@as(usize, 2), head.nrows());
    try test_support.expectStrings(&.{ "cara", "3" }, head.row(0));
    try test_support.expectStrings(&.{ "bob", "2" }, head.row(1));

    const tail = try Table.initCsv(testing.allocator, .{ .reverse = true, .tail = 2 }, "name,score\nalice,1\nbob,2\ncara,3\n");
    defer tail.deinit();
    try testing.expectEqual(@as(usize, 2), tail.nrows());
    try test_support.expectStrings(&.{ "bob", "2" }, tail.row(0));
    try test_support.expectStrings(&.{ "alice", "1" }, tail.row(1));
}

test "table reverses sorted rows" {
    const table = try Table.initCsv(testing.allocator, .{ .sort = "name", .reverse = true }, "name,score\nbob,2\nalice,1\ncara,3\n");
    defer table.deinit();

    try test_support.expectStrings(&.{ "cara", "3" }, table.row(0));
    try test_support.expectStrings(&.{ "bob", "2" }, table.row(1));
    try test_support.expectStrings(&.{ "alice", "1" }, table.row(2));
}

test "table shuffles rows with a seeded config" {
    const table = try Table.initCsv(testing.allocator, .{ .shuffle = true, .srand = 1 }, "name,score\nalice,1\nbob,2\ncara,3\ndina,4\n");
    defer table.deinit();

    try testing.expectEqualSlices(usize, &.{ 3, 0, 2, 1 }, table.row_view);
    try test_support.expectStrings(&.{ "dina", "4" }, table.row(0));
    try test_support.expectStrings(&.{ "alice", "1" }, table.row(1));
    try test_support.expectStrings(&.{ "cara", "3" }, table.row(2));
    try test_support.expectStrings(&.{ "bob", "2" }, table.row(3));
}

test "table shuffles before head and tail" {
    const head = try Table.initCsv(testing.allocator, .{ .shuffle = true, .srand = 1, .head = 2 }, "name,score\nalice,1\nbob,2\ncara,3\ndina,4\n");
    defer head.deinit();
    try testing.expectEqual(@as(usize, 2), head.nrows());
    try test_support.expectStrings(&.{ "dina", "4" }, head.row(0));
    try test_support.expectStrings(&.{ "alice", "1" }, head.row(1));

    const tail = try Table.initCsv(testing.allocator, .{ .shuffle = true, .srand = 1, .tail = 2 }, "name,score\nalice,1\nbob,2\ncara,3\ndina,4\n");
    defer tail.deinit();
    try testing.expectEqual(@as(usize, 2), tail.nrows());
    try test_support.expectStrings(&.{ "cara", "3" }, tail.row(0));
    try test_support.expectStrings(&.{ "bob", "2" }, tail.row(1));
}

test "nrows clamps oversized head and tail" {
    const head = try Table.initCsv(testing.allocator, .{ .head = 100 }, "a,b\n1,2\n3,4\n");
    defer head.deinit();
    try testing.expectEqual(@as(usize, 2), head.nrows());
    try testing.expectEqual(@as(usize, 2), head.lastRowNumber());

    const tail = try Table.initCsv(testing.allocator, .{ .tail = 100 }, "a,b\n1,2\n3,4\n");
    defer tail.deinit();
    try testing.expectEqual(@as(usize, 2), tail.nrows());
    try testing.expectEqual(@as(usize, 2), tail.lastRowNumber());
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
