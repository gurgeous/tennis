// Parsed table data plus rendering-time caches and helpers.
pub const Table = struct {
    alloc: std.mem.Allocator,
    data: Data = .{ .rows = &.{} },
    header: ?DataRow = null,
    rows: []DataRow = &.{},
    columns: []Column,
    config: Config = .{},
    empty: bool = false,
    _style: ?Style = null,
    _term_width: ?usize = null,

    const Self = @This();

    //
    // init/deinit
    //

    // Build a table from pre-parsed stored rows.
    pub fn init(alloc: std.mem.Allocator, config: Config, data: Data) !*Table {
        const table = try alloc.create(Table);
        errdefer alloc.destroy(table);

        const empty = data.rows.len < 2;
        table.* = .{
            .alloc = alloc,
            .columns = &.{},
            .config = config,
            .data = data,
            .empty = empty,
        };
        errdefer table.deinit();

        // rows
        var timer = util.timerStart();
        if (!table.empty) table.rows = try table.buildRows();
        util.benchmark(" table.rows", util.timerRead(timer));

        // cols
        timer = util.timerStart();
        table.columns = try table.buildColumns();
        util.benchmark(" table.cols", util.timerRead(timer));

        return table;
    }

    // This is just for testing at the moment
    pub fn initCsv(alloc: std.mem.Allocator, config: Config, bytes: []const u8) !*Table {
        const data = try csv.load(alloc, bytes, config.delimiter);
        errdefer data.deinit(alloc);
        var bound = config;
        if (config.title.len > 0) bound.title = try alloc.dupe(u8, config.title);
        if (config.footer.len > 0) bound.footer = try alloc.dupe(u8, config.footer);
        var handed_off = false;
        defer if (!handed_off) bound.deinit(alloc);
        try bound.bind(alloc, data.headers());
        const table = try init(alloc, bound, data);
        handed_off = true;
        return table;
    }

    // Release the table, columns, style cache, and stored rows.
    pub fn deinit(self: *Self) void {
        for (self.columns) |col| col.deinit(self.alloc);
        self.alloc.free(self.columns);
        if (self.header) |header| header.deinit(self.alloc);
        if (self.rows.len > 0) {
            for (self.rows) |data_row| data_row.deinit(self.alloc);
            self.alloc.free(self.rows);
        }
        self.data.deinit(self.alloc);
        self.config.deinit(self.alloc);
        self.alloc.destroy(self);
    }

    //
    // main
    //

    // Render this table to the provided writer.
    pub fn renderTable(self: *Self, writer: *std.Io.Writer) !void {
        var timer = util.timerStart();
        const layout = try Layout.init(self);
        defer layout.deinit(self.alloc);
        util.benchmark(" render.layout", util.timerRead(timer));

        var renderer: Render = .init(self, writer, layout);
        defer renderer.deinit();
        timer = util.timerStart();
        try renderer.render();
        util.benchmark(" render.output", util.timerRead(timer));
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
        return if (self.header) |header| header.row else &.{};
    }

    // Return the number of visible rows after clipping.
    pub fn nrows(self: *const Self) usize {
        return self.rows.len;
    }

    // note: does not include row-number column
    // Return the number of columns in the table.
    pub fn ncols(self: *const Self) usize {
        return self.headers().len;
    }

    // Return one visible data row.
    pub fn row(self: *const Self, index: usize) Row {
        return self.rows[index].row;
    }

    // Return one built column view.
    pub fn column(self: *const Self, index: usize) Column {
        return self.columns[index];
    }

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
            self._term_width = switch (self.config.width) {
                .chars => |width| width,
                else => util.termWidth(),
            };
        }
        return self._term_width.?;
    }

    //
    // build final rows/cols, which are a view into data
    //

    // Apply all row/col transforms and return the final visible rows.
    fn buildRows(self: *Self) ![]DataRow {
        // row_order and --filter
        const row_order = try if (self.config.filter.len > 0)
            self.filterRows()
        else
            util.range(self.alloc, self.data.rows.len - 1);
        defer self.alloc.free(row_order);

        // col_order and --select/--deselect
        var col_order = try if (self.config.select_cols.len > 0)
            self.alloc.dupe(usize, self.config.select_cols)
        else
            util.range(self.alloc, self.data.headers().len);
        defer self.alloc.free(col_order);
        if (self.config.deselect_cols.len > 0) {
            const next = try self.deselectCols(col_order);
            self.alloc.free(col_order);
            col_order = next;
            if (col_order.len == 0) return error.InvalidDeselect;
        }

        // --sort / --shuffle / --reverse
        if (self.config.sort_cols.len > 0) {
            const sorter: sort.Sort = .{ .cols = self.config.sort_cols };
            sorter.apply(self.data, row_order);
        }
        if (self.config.shuffle) {
            const seed = if (self.config.srand != 0) self.config.srand else randomSeed();
            var prng = std.Random.DefaultPrng.init(seed);
            prng.random().shuffle(usize, row_order);
        }
        if (self.config.reverse) std.mem.reverse(usize, row_order);

        // --head/--tail
        var n = row_order.len;
        if (self.config.head > 0) n = @min(self.config.head, n);
        if (self.config.tail > 0) n = @min(self.config.tail, n);
        const start = if (self.config.tail > 0) row_order.len - n else 0;
        const clipped = row_order[start .. start + n];
        self.header = try DataRow.project(self.alloc, self.data.headers(), col_order);

        // col_order & row_order => our rows
        var rows: std.ArrayList(DataRow) = .empty;
        defer {
            for (rows.items) |data_row| data_row.deinit(self.alloc);
            rows.deinit(self.alloc);
        }
        try rows.ensureTotalCapacity(self.alloc, clipped.len);
        for (clipped) |ii| try rows.append(self.alloc, try DataRow.project(self.alloc, self.data.row(ii + 1), col_order));
        return try rows.toOwnedSlice(self.alloc);
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

    // Return row indexes where any field contains the case-insensitive filter text.
    fn filterRows(self: *const Self) ![]usize {
        var out: std.ArrayList(usize) = .empty;
        defer out.deinit(self.alloc);

        for (self.data.rows[1..], 0..) |r, ii| {
            for (r.row) |field| {
                if (util.containsIgnoreCase(field, self.config.filter)) {
                    try out.append(self.alloc, ii);
                    break;
                }
            }
        }
        return out.toOwnedSlice(self.alloc);
    }

    // Remove bound deselected columns from the current visible column order.
    fn deselectCols(self: *const Self, col_order: []const usize) ![]usize {
        var out: std.ArrayList(usize) = .empty;
        defer out.deinit(self.alloc);

        for (col_order) |source_col| {
            if (std.mem.indexOfScalar(usize, self.config.deselect_cols, source_col) == null) {
                try out.append(self.alloc, source_col);
            }
        }
        return out.toOwnedSlice(self.alloc);
    }

    // Generate one unpredictable PRNG seed from the runtime IO entropy source.
    fn randomSeed() u64 {
        var bytes: [8]u8 = undefined;
        util.getIo().random(&bytes);
        return std.mem.readInt(u64, &bytes, .little);
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

        try test_support.expectEqualRows(tc.headers, table.headers());
        try testing.expectEqual(tc.nrows, table.nrows());
        try testing.expectEqual(tc.ncols, table.ncols());
        try testing.expectEqual(tc.empty, table.isEmpty());
        if (tc.first_row) |row| try test_support.expectEqualRows(row, table.row(0));
        if (tc.empty and tc.input.len > 0) try testing.expectEqual(@as(usize, 0), table.columns.len);
    }
}

test "deselect removes columns after select" {
    const table = try Table.initCsv(testing.allocator, .{
        .select = "score,name,city",
        .deselect = "city,score",
    }, "name,score,city\nalice,123,boston\n");
    defer table.deinit();

    try test_support.expectEqualRows(&.{"name"}, table.headers());
    try test_support.expectEqualRows(&.{"alice"}, table.row(0));
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
        for (tc.rows, 0..) |want, ii| try test_support.expectEqualRows(want, table.row(ii));
    }
}

test "table sorts rows by one column" {
    const table = try Table.initCsv(testing.allocator, .{ .sort = "name" }, "name,score\nbob,2\nalice,1\ncara,3\n");
    defer table.deinit();

    try test_support.expectEqualRows(&.{ "alice", "1" }, table.row(0));
    try test_support.expectEqualRows(&.{ "bob", "2" }, table.row(1));
    try test_support.expectEqualRows(&.{ "cara", "3" }, table.row(2));
}

test "table sorts rows by multiple columns" {
    const table = try Table.initCsv(testing.allocator, .{ .sort = "city,name" }, "name,city\nbob,denver\ncara,boston\nalice,boston\n");
    defer table.deinit();

    try test_support.expectEqualRows(&.{ "alice", "boston" }, table.row(0));
    try test_support.expectEqualRows(&.{ "cara", "boston" }, table.row(1));
    try test_support.expectEqualRows(&.{ "bob", "denver" }, table.row(2));
}

test "table sorts with case insensitive header match" {
    const table = try Table.initCsv(testing.allocator, .{ .sort = "NAME" }, "name,score\nbob,2\nalice,1\n");
    defer table.deinit();

    try test_support.expectEqualRows(&.{ "alice", "1" }, table.row(0));
    try test_support.expectEqualRows(&.{ "bob", "2" }, table.row(1));
}

test "table selects a subset of columns" {
    const table = try Table.initCsv(testing.allocator, .{ .select = "score,name" }, "name,score,city\nbob,2,denver\nalice,1,boston\n");
    defer table.deinit();

    try test_support.expectEqualRows(&.{ "score", "name" }, table.headers());
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
    try test_support.expectEqualRows(&.{ "Alice", "1", "boston" }, table.row(0));
    try test_support.expectEqualRows(&.{ "mali", "3", "paris" }, table.row(1));
}

test "table filters before sort and head" {
    const table = try Table.initCsv(testing.allocator, .{ .filter = "bo", .sort = "score", .head = 1 }, "name,score,city\nbob,2,denver\nAlice,1,boston\nmali,3,paris\nboris,4,rome\n");
    defer table.deinit();

    try testing.expectEqual(@as(usize, 1), table.nrows());
    try test_support.expectEqualRows(&.{ "Alice", "1", "boston" }, table.row(0));
}

test "table select supports duplicates" {
    const table = try Table.initCsv(testing.allocator, .{ .select = "name,score,name" }, "name,score\nbob,2\n");
    defer table.deinit();

    try test_support.expectEqualRows(&.{ "name", "score", "name" }, table.headers());
    try testing.expectEqual(@as(usize, 3), table.ncols());
    try testing.expectEqualStrings("bob", table.column(0).field(0));
    try testing.expectEqualStrings("2", table.column(1).field(0));
    try testing.expectEqualStrings("bob", table.column(2).field(0));
}

test "table sorts using hidden columns after select" {
    const table = try Table.initCsv(testing.allocator, .{ .select = "name", .sort = "score" }, "name,score\nbob,2\nalice,1\n");
    defer table.deinit();

    try test_support.expectEqualRows(&.{"name"}, table.headers());
    try testing.expectEqual(@as(usize, 1), table.ncols());
    try testing.expectEqualStrings("alice", table.column(0).field(0));
    try testing.expectEqualStrings("bob", table.column(0).field(1));
}

test "table sorts before head and tail" {
    const head = try Table.initCsv(testing.allocator, .{ .sort = "name", .head = 2 }, "name,score\ncara,3\nbob,2\nalice,1\n");
    defer head.deinit();
    try testing.expectEqual(@as(usize, 2), head.nrows());
    try test_support.expectEqualRows(&.{ "alice", "1" }, head.row(0));
    try test_support.expectEqualRows(&.{ "bob", "2" }, head.row(1));

    const tail = try Table.initCsv(testing.allocator, .{ .sort = "name", .tail = 2 }, "name,score\ncara,3\nbob,2\nalice,1\n");
    defer tail.deinit();
    try testing.expectEqual(@as(usize, 2), tail.nrows());
    try test_support.expectEqualRows(&.{ "bob", "2" }, tail.row(0));
    try test_support.expectEqualRows(&.{ "cara", "3" }, tail.row(1));
}

test "table reverses rows before head and tail" {
    const head = try Table.initCsv(testing.allocator, .{ .reverse = true, .head = 2 }, "name,score\nalice,1\nbob,2\ncara,3\n");
    defer head.deinit();
    try testing.expectEqual(@as(usize, 2), head.nrows());
    try test_support.expectEqualRows(&.{ "cara", "3" }, head.row(0));
    try test_support.expectEqualRows(&.{ "bob", "2" }, head.row(1));

    const tail = try Table.initCsv(testing.allocator, .{ .reverse = true, .tail = 2 }, "name,score\nalice,1\nbob,2\ncara,3\n");
    defer tail.deinit();
    try testing.expectEqual(@as(usize, 2), tail.nrows());
    try test_support.expectEqualRows(&.{ "bob", "2" }, tail.row(0));
    try test_support.expectEqualRows(&.{ "alice", "1" }, tail.row(1));
}

test "table reverses sorted rows" {
    const table = try Table.initCsv(testing.allocator, .{ .sort = "name", .reverse = true }, "name,score\nbob,2\nalice,1\ncara,3\n");
    defer table.deinit();

    try test_support.expectEqualRows(&.{ "cara", "3" }, table.row(0));
    try test_support.expectEqualRows(&.{ "bob", "2" }, table.row(1));
    try test_support.expectEqualRows(&.{ "alice", "1" }, table.row(2));
}

test "table shuffles rows with a seeded config" {
    const table = try Table.initCsv(testing.allocator, .{ .shuffle = true, .srand = 1 }, "name,score\nalice,1\nbob,2\ncara,3\ndina,4\n");
    defer table.deinit();

    try test_support.expectEqualRows(&.{ "dina", "4" }, table.row(0));
    try test_support.expectEqualRows(&.{ "alice", "1" }, table.row(1));
    try test_support.expectEqualRows(&.{ "cara", "3" }, table.row(2));
    try test_support.expectEqualRows(&.{ "bob", "2" }, table.row(3));
}

test "table shuffles before head and tail" {
    const head = try Table.initCsv(testing.allocator, .{ .shuffle = true, .srand = 1, .head = 2 }, "name,score\nalice,1\nbob,2\ncara,3\ndina,4\n");
    defer head.deinit();
    try testing.expectEqual(@as(usize, 2), head.nrows());
    try test_support.expectEqualRows(&.{ "dina", "4" }, head.row(0));
    try test_support.expectEqualRows(&.{ "alice", "1" }, head.row(1));

    const tail = try Table.initCsv(testing.allocator, .{ .shuffle = true, .srand = 1, .tail = 2 }, "name,score\nalice,1\nbob,2\ncara,3\ndina,4\n");
    defer tail.deinit();
    try testing.expectEqual(@as(usize, 2), tail.nrows());
    try test_support.expectEqualRows(&.{ "cara", "3" }, tail.row(0));
    try test_support.expectEqualRows(&.{ "bob", "2" }, tail.row(1));
}

test "nrows clamps oversized head and tail" {
    const head = try Table.initCsv(testing.allocator, .{ .head = 100 }, "a,b\n1,2\n3,4\n");
    defer head.deinit();
    try testing.expectEqual(@as(usize, 2), head.nrows());

    const tail = try Table.initCsv(testing.allocator, .{ .tail = 100 }, "a,b\n1,2\n3,4\n");
    defer tail.deinit();
    try testing.expectEqual(@as(usize, 2), tail.nrows());
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
    const table = try Table.initCsv(testing.allocator, .{ .width = .{ .chars = 123 } }, "a,b\nc,d\n");
    defer table.deinit();

    try testing.expectEqual(@as(usize, 123), table.termWidth());
}

const Column = @import("column.zig").Column;
const csv = @import("csv.zig");
const Data = @import("data.zig").Data;
const DataRow = @import("data.zig").DataRow;
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
const Config = types.Config;
