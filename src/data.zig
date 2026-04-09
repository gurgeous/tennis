// Stores parsed table rows in memory.

// Bunch of rows.
pub const Data = struct {
    // Header row plus any loaded data rows.
    rows: []DataRow,

    // Release all owned row slices and row buffers.
    pub fn deinit(self: Data, alloc: std.mem.Allocator) void {
        for (self.rows) |owned| owned.deinit(alloc);
        alloc.free(self.rows);
    }

    pub fn row(self: Data, index: usize) Row {
        return self.rows[index].row;
    }

    pub fn headers(self: Data) Row {
        return if (self.rows.len > 0) self.row(0) else &.{};
    }
};

// Clone a header row plus up to `limit` data rows into owned storage.
pub fn cloneRows(alloc: std.mem.Allocator, headers: Row, rows: []const Row, limit: ?usize) !Data {
    const n = if (limit) |max_rows| @min(max_rows, rows.len) else rows.len;
    const out = try alloc.alloc(DataRow, n + 1);
    errdefer alloc.free(out);

    var ii: usize = 0;
    errdefer {
        for (out[0..ii]) |row| row.deinit(alloc);
    }

    out[ii] = try DataRow.init(alloc, headers);
    ii += 1;
    for (rows[0..n]) |row| {
        out[ii] = try DataRow.init(alloc, row);
        ii += 1;
    }
    return .{ .rows = out };
}

// One row and the backing bytes referenced by its fields.
pub const DataRow = struct {
    row: Row,
    buf: []const u8,

    // Copy arbitrary fields into one owned row buffer with shared normalization.
    pub fn init(alloc: std.mem.Allocator, row_in: []const Field) !DataRow {
        const row = try alloc.alloc(Field, row_in.len);
        errdefer alloc.free(row);

        // if we think the cell might contain \t \r \n, use the slow path
        var slow = false;
        var len: usize = 0;
        for (row_in, 0..) |field, ii| {
            // Intentionally strip cells for nice display
            const str = util.strip(u8, field);
            row[ii] = str;
            if (hasControl(str)) {
                slow = true;
            }
            len += str.len;
        }

        return if (slow) initSlow(alloc, row) else initFast(alloc, row, len);
    }

    // Copy selected source columns into one owned row buffer with shared normalization.
    pub fn project(alloc: std.mem.Allocator, source: Row, col_order: []const usize) !DataRow {
        const row = try alloc.alloc(Field, col_order.len);
        errdefer alloc.free(row);

        var slow = false;
        var len: usize = 0;
        for (col_order, 0..) |col, ii| {
            // Intentionally strip cells for nice display
            const str = util.strip(u8, source[col]);
            row[ii] = str;
            if (hasControl(str)) slow = true;
            len += str.len;
        }

        return if (slow) initSlow(alloc, row) else initFast(alloc, row, len);
    }

    fn initFast(alloc: std.mem.Allocator, row: []Field, len: usize) !DataRow {
        const buf = try alloc.alloc(u8, len);
        errdefer alloc.free(buf);

        var cursor: usize = 0;
        for (row, 0..) |field, ii| {
            const end = cursor + field.len;
            const out = buf[cursor..end];
            @memcpy(out, field);
            row[ii] = out;
            cursor = end;
        }

        return .{ .row = row, .buf = buf };
    }

    fn initSlow(alloc: std.mem.Allocator, row: []Field) !DataRow {
        // build list => buf
        var list: std.ArrayList(u8) = .empty;
        defer list.deinit(alloc);
        for (row, 0..) |field, ii| {
            if (ii > 0) try list.append(alloc, '\t');
            try appendNormalized(alloc, &list, field);
        }
        const buf = try list.toOwnedSlice(alloc);

        // split into fields
        var iter = std.mem.splitScalar(u8, buf, '\t');
        for (row) |*field| field.* = iter.next().?;
        return .{ .row = row, .buf = buf };
    }

    pub fn deinit(self: DataRow, alloc: std.mem.Allocator) void {
        alloc.free(self.row);
        alloc.free(self.buf);
    }
};

fn hasControl(field: Field) bool {
    for (field) |ch| {
        if (ch < ' ') return true;
    }
    return false;
}

fn appendNormalized(alloc: std.mem.Allocator, out: *std.ArrayList(u8), field: Field) !void {
    for (field) |ch| switch (ch) {
        '\n' => try out.appendSlice(alloc, "\\n"),
        '\r' => try out.appendSlice(alloc, "\\r"),
        '\t' => try out.appendSlice(alloc, "\\t"),
        else => try out.append(alloc, ch),
    };
}

//
// testing
//

test "DataRow.init copies disjoint slices into one owned row" {
    const alloc = testing.allocator;
    const left = "ab";
    const right = "cd";

    const got = try DataRow.init(alloc, &.{ left[0..1], right[1..2] });
    defer got.deinit(alloc);

    try testing.expectEqual(@as(usize, 2), got.row.len);
    try testing.expectEqualStrings("a", got.row[0]);
    try testing.expectEqualStrings("d", got.row[1]);
    try testing.expectEqualStrings("ad", got.buf);
}

test "DataRow.project copies selected columns into one owned row" {
    const alloc = testing.allocator;
    const got = try DataRow.project(alloc, &.{ " c ", "a\tb", "d" }, &.{ 1, 0, 1 });
    defer got.deinit(alloc);

    try testing.expectEqual(@as(usize, 3), got.row.len);
    try testing.expectEqualStrings("a\\tb", got.row[0]);
    try testing.expectEqualStrings("c", got.row[1]);
    try testing.expectEqualStrings("a\\tb", got.row[2]);
}

test "Data.headers returns first row or empty" {
    const alloc = testing.allocator;

    const full = try alloc.alloc(DataRow, 1);
    errdefer alloc.free(full);
    full[0] = try DataRow.init(alloc, &.{ "a", "b" });
    var data: Data = .{ .rows = full };
    defer data.deinit(alloc);
    try testing.expectEqual(@as(usize, 2), data.headers().len);
    try testing.expectEqualStrings("a", data.headers()[0]);
    try testing.expectEqualStrings("b", data.headers()[1]);

    const empty_rows = try alloc.alloc(DataRow, 0);
    var empty: Data = .{ .rows = empty_rows };
    defer empty.deinit(alloc);
    try testing.expectEqual(@as(usize, 0), empty.headers().len);
}

test "cloneRows clones headers and respects optional limit" {
    const alloc = testing.allocator;
    const data = try cloneRows(alloc, &.{ "a", "b" }, &.{ &.{ "1", "2" }, &.{ "3", "4" } }, 1);
    defer data.deinit(alloc);

    try testing.expectEqual(@as(usize, 2), data.rows.len);
    try testing.expectEqualStrings("a", data.row(0)[0]);
    try testing.expectEqualStrings("1", data.row(1)[0]);
}

test "cloneRows clones all rows when limit is null" {
    const alloc = testing.allocator;
    const data = try cloneRows(alloc, &.{"a"}, &.{ &.{"1"}, &.{"2"} }, null);
    defer data.deinit(alloc);

    try testing.expectEqual(@as(usize, 3), data.rows.len);
    try testing.expectEqualStrings("2", data.row(2)[0]);
}

test "DataRow.init strips and escapes newlines" {
    const alloc = testing.allocator;
    const got = try DataRow.init(alloc, &.{" a\nhi\rb "});
    defer got.deinit(alloc);

    try testing.expectEqual(@as(usize, 1), got.row.len);
    try testing.expectEqualStrings("a\\nhi\\rb", got.row[0]);
    try testing.expectEqualStrings("a\\nhi\\rb", got.buf);
}

test "DataRow.init escapes CRLF pairs" {
    const alloc = testing.allocator;
    const got = try DataRow.init(alloc, &.{"a\r\nb"});
    defer got.deinit(alloc);

    try testing.expectEqual(@as(usize, 1), got.row.len);
    try testing.expectEqualStrings("a\\r\\nb", got.row[0]);
}

test "DataRow.init strips whitespace-only fields to empty" {
    const alloc = testing.allocator;
    const got = try DataRow.init(alloc, &.{ " \t ", "\r\n" });
    defer got.deinit(alloc);

    try testing.expectEqual(@as(usize, 2), got.row.len);
    try testing.expectEqualStrings("", got.row[0]);
    try testing.expectEqualStrings("", got.row[1]);
    try testing.expectEqualStrings("", got.buf);
}

test "DataRow.init escapes tabs" {
    const alloc = testing.allocator;
    const got = try DataRow.init(alloc, &.{"a\tb"});
    defer got.deinit(alloc);

    try testing.expectEqual(@as(usize, 1), got.row.len);
    try testing.expectEqualStrings("a\\tb", got.row[0]);
}

test "DataRow.init slow path handles mixed fields" {
    const alloc = testing.allocator;
    const got = try DataRow.init(alloc, &.{ "a\tb", "", "x\ny", "z" });
    defer got.deinit(alloc);

    try testing.expectEqual(@as(usize, 4), got.row.len);
    try testing.expectEqualStrings("a\\tb", got.row[0]);
    try testing.expectEqualStrings("", got.row[1]);
    try testing.expectEqualStrings("x\\ny", got.row[2]);
    try testing.expectEqualStrings("z", got.row[3]);
}

test "DataRow.init slow path preserves empty leading and trailing fields" {
    const alloc = testing.allocator;
    const got = try DataRow.init(alloc, &.{ "", "a\r\nb", "" });
    defer got.deinit(alloc);

    try testing.expectEqual(@as(usize, 3), got.row.len);
    try testing.expectEqualStrings("", got.row[0]);
    try testing.expectEqualStrings("a\\r\\nb", got.row[1]);
    try testing.expectEqualStrings("", got.row[2]);
}

test "DataRow.init slow path handles many escaped fields" {
    const alloc = testing.allocator;
    const got = try DataRow.init(alloc, &.{ "a\n", "b\r", "c\td", "a\tb\nc\rd" });
    defer got.deinit(alloc);

    try testing.expectEqual(@as(usize, 4), got.row.len);
    try testing.expectEqualStrings("a", got.row[0]);
    try testing.expectEqualStrings("b", got.row[1]);
    try testing.expectEqualStrings("c\\td", got.row[2]);
    try testing.expectEqualStrings("a\\tb\\nc\\rd", got.row[3]);
}

const Field = @import("types.zig").Field;
const Row = @import("types.zig").Row;
const std = @import("std");
const testing = std.testing;
const util = @import("util.zig");
