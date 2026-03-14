pub const Table = struct {
    // passed into init
    alloc: std.mem.Allocator,
    csv: Csv,
    config: types.Config = .{},
    empty: bool = false,
    // calculated from config + terminal
    style_cache: ?Style = null,
    term_width: ?usize = null,

    //
    // init/deinit
    //

    pub fn init(alloc: std.mem.Allocator, config: types.Config, reader: anytype) !Table {
        const csv = try Csv.init(alloc, reader);

        // A csv with zero data rows is intentionally rendered as an "empty
        // table", even if the parser produced a single header row.
        const empty = csv.rows.len < 2 or csv.rows[0].len == 0;

        return .{
            .alloc = alloc,
            .config = config,
            .csv = csv,
            .empty = empty,
        };
    }

    pub fn deinit(self: *Table) void {
        self.csv.deinit(self.alloc);
    }

    //
    // main
    //

    pub fn renderTable(self: *Table, writer: *std.Io.Writer) !void {
        const layout = try Layout.init(self);
        defer layout.deinit(self.alloc);

        var renderer: Render = .init(self, writer, layout);
        defer renderer.deinit();
        try renderer.render();
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

    pub fn ncols(self: *const Table) usize {
        if (self.empty) return 0;
        return self.csv.rows[0].len;
    }

    pub fn rows(self: *const Table) Rows {
        if (self.empty) return &.{};
        return self.csv.rows[1..];
    }

    pub fn column(self: *const Table, index: usize) ColumnIterator {
        return .{ .rows = self.rows(), .index = index };
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
};

pub const ColumnIterator = struct {
    rows: Rows,
    index: usize,
    row_index: usize = 0,

    pub fn next(self: *ColumnIterator) ?Field {
        if (self.row_index >= self.rows.len) return null;
        const field = self.rows[self.row_index][self.index];
        self.row_index += 1;
        return field;
    }
};

test "headers length and emptiness reflect table shape" {
    var in = std.io.fixedBufferStream("a,b\nc,d\n");
    var table = try Table.init(std.testing.allocator, .{}, in.reader());
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
    var table = try Table.init(std.testing.allocator, .{}, in.reader());
    defer table.deinit();

    try std.testing.expectEqual(@as(usize, 0), table.headers().len);
    try std.testing.expectEqual(@as(usize, 0), table.nrows());
    try std.testing.expectEqual(@as(usize, 0), table.ncols());
    try std.testing.expect(table.isEmpty());
}

test "header only input is empty" {
    var in = std.io.fixedBufferStream("a,b\n");
    var table = try Table.init(std.testing.allocator, .{}, in.reader());
    defer table.deinit();

    try std.testing.expect(table.isEmpty());
    try std.testing.expectEqual(@as(usize, 0), table.headers().len);
    try std.testing.expectEqual(@as(usize, 0), table.nrows());
}

test "rows returns data rows only" {
    var in = std.io.fixedBufferStream("a,b\nc,d\ne,f\n");
    var table = try Table.init(std.testing.allocator, .{}, in.reader());
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

test "column iterator returns column values for data rows only" {
    var in = std.io.fixedBufferStream("a,b\nc,d\ne,f\n");
    var table = try Table.init(std.testing.allocator, .{}, in.reader());
    defer table.deinit();

    var column = table.column(1);
    try std.testing.expectEqualStrings("d", column.next().?);
    try std.testing.expectEqualStrings("f", column.next().?);
    try std.testing.expectEqual(@as(?Field, null), column.next());
}

test "column iterator is empty for empty table" {
    var in = std.io.fixedBufferStream("a,b\n");
    var table = try Table.init(std.testing.allocator, .{}, in.reader());
    defer table.deinit();

    var column = table.column(0);
    try std.testing.expectEqual(@as(?Field, null), column.next());
}

test "style respects config" {
    var in = std.io.fixedBufferStream("a,b\nc,d\n");
    var table1 = try Table.init(std.testing.allocator, .{ .color = .off, .theme = .dark }, in.reader());
    defer table1.deinit();
    try std.testing.expectEqualStrings("", table1.style().title);
    try std.testing.expectEqualStrings("", table1.style().chrome);

    var in2 = std.io.fixedBufferStream("a,b\nc,d\n");
    var table2 = try Table.init(std.testing.allocator, .{ .color = .on, .theme = .dark }, in2.reader());
    defer table2.deinit();
    try std.testing.expect(table2.style().title.len > 0);
    try std.testing.expect(table2.style().chrome.len > 0);
}

test "termWidth respects config width" {
    var in = std.io.fixedBufferStream("a,b\nc,d\n");
    var table = try Table.init(std.testing.allocator, .{ .width = 123 }, in.reader());
    defer table.deinit();

    try std.testing.expectEqual(@as(usize, 123), table.termWidth());
}

const Csv = @import("csv.zig").Csv;
const Layout = @import("layout.zig").Layout;
const Render = @import("render.zig").Render;
const std = @import("std");
const Style = @import("style.zig").Style;
const types = @import("types.zig");
const util = @import("util.zig");
const Field = @import("types.zig").Field;
const Row = @import("types.zig").Row;
const Rows = @import("types.zig").Rows;
