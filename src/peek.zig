// Build and render a compact sample + stats view for one visible table.
pub fn render(alloc: std.mem.Allocator, table: *Table, writer: *std.Io.Writer) !void {
    const sample = try buildSampleTable(alloc, table);
    defer sample.config.deinit(alloc);
    defer sample.deinit();
    try sample.renderTable(writer);

    try writer.writeByte('\n');

    const stats = try buildStatsTable(alloc, table);
    defer stats.config.deinit(alloc);
    defer stats.deinit();
    try stats.renderTable(writer);
}

// Build a small visible-row sample table with shape embedded in the title.
fn buildSampleTable(alloc: std.mem.Allocator, table: *Table) !*Table {
    var config = sampleConfig(table.config);
    const title = try shapeTitle(alloc, table.config.title, table.nrows(), table.ncols());
    config.title = title;
    config.owned_title = title;

    const n = @min(@as(usize, 5), table.nrows());
    if (table.nrows() > n) {
        const more = table.nrows() - n;
        const footer = try sampleFooter(alloc, more);
        config.footer = footer;
        config.owned_footer = footer;
    }
    var rows: std.ArrayList(DataRow) = .empty;
    defer {
        for (rows.items) |row| row.deinit(alloc);
        rows.deinit(alloc);
    }
    try rows.ensureTotalCapacity(alloc, n + 1);
    try rows.append(alloc, try DataRow.init(alloc, table.headers()));
    for (0..n) |ii| try rows.append(alloc, try DataRow.init(alloc, table.row(ii)));

    return try Table.init(alloc, config, .{ .rows = try rows.toOwnedSlice(alloc) });
}

// Build one visible-column stats table for the current visible table.
fn buildStatsTable(alloc: std.mem.Allocator, table: *Table) !*Table {
    const headers = [_]Field{ "column", "type", "fill", "uniq", "min", "max" };
    var rows: std.ArrayList(DataRow) = .empty;
    defer {
        for (rows.items) |row| row.deinit(alloc);
        rows.deinit(alloc);
    }
    try rows.ensureTotalCapacity(alloc, table.ncols() + 1);
    try rows.append(alloc, try DataRow.init(alloc, &headers));
    for (0..table.ncols()) |ii| try rows.append(alloc, try buildStatsRow(alloc, table, ii));

    return try Table.init(alloc, statsConfig(table.config), .{ .rows = try rows.toOwnedSlice(alloc) });
}

// Build one owned stats row for one visible column.
fn buildStatsRow(alloc: std.mem.Allocator, table: *Table, visible_col: usize) !DataRow {
    const column = table.column(visible_col);
    const fill = try formatFill(alloc, table, visible_col);
    defer alloc.free(fill);
    const uniq = try formatUniq(alloc, table, visible_col);
    defer alloc.free(uniq);
    const min = try formatMin(alloc, table, visible_col);
    defer alloc.free(min);
    const max = try formatMax(alloc, table, visible_col);
    defer alloc.free(max);

    const row = [_]Field{
        table.headers()[visible_col],
        @tagName(column.type),
        fill,
        uniq,
        min,
        max,
    };
    return try DataRow.init(alloc, &row);
}

// Format the sample/stats title with the current visible shape.
fn shapeTitle(alloc: std.mem.Allocator, title: []const u8, nrows: usize, ncols: usize) ![]u8 {
    const rows = try formatCount(alloc, nrows);
    defer alloc.free(rows);
    const cols = try formatCount(alloc, ncols);
    defer alloc.free(cols);
    const row_word = util.plural(nrows, "row", "rows");
    const col_word = util.plural(ncols, "col", "cols");

    if (title.len > 0) {
        return std.fmt.allocPrint(alloc, "{s} ({s} {s} × {s} {s})", .{ title, rows, row_word, cols, col_word });
    }
    return std.fmt.allocPrint(alloc, "{s} {s} × {s} {s}", .{ rows, row_word, cols, col_word });
}

// Format one count with thousands separators for titles and stats.
fn formatCount(alloc: std.mem.Allocator, n: usize) ![]u8 {
    var buf: [32]u8 = undefined;
    const raw = try std.fmt.bufPrint(&buf, "{d}", .{n});
    return int.intFormat(alloc, raw);
}

// Derive a config for the sample table without reapplying row/col transforms.
fn sampleConfig(config: Config) Config {
    var out = config;
    out.filter = "";
    out.footer = "";
    out.head = 0;
    out.peek = false;
    out.reverse = false;
    out.select = "";
    out.select_cols = &.{};
    out.shuffle = false;
    out.sort = "";
    out.sort_cols = &.{};
    out.tail = 0;
    out.owned_footer = null;
    out.owned_title = null;
    out.srand = 0;
    return out;
}

// Derive a config for the stats table.
fn statsConfig(config: Config) Config {
    var out = sampleConfig(config);
    out.row_numbers = false;
    out.title = "stats";
    return out;
}

// Format the centered sample footer when the sample omits visible rows.
fn sampleFooter(alloc: std.mem.Allocator, nmore: usize) ![]u8 {
    const more = try formatCount(alloc, nmore);
    defer alloc.free(more);
    return std.fmt.allocPrint(alloc, "… {s} more {s} …", .{ more, util.plural(nmore, "row", "rows") });
}

// Format fill as the percent of non-empty visible cells in a column.
fn formatFill(alloc: std.mem.Allocator, table: *Table, visible_col: usize) ![]u8 {
    if (table.nrows() == 0) return alloc.dupe(u8, "0%");

    var fill: usize = 0;
    for (0..table.nrows()) |visible_row| {
        if (table.row(visible_row)[visible_col].len > 0) fill += 1;
    }
    const pct = (fill * 100 + table.nrows() / 2) / table.nrows();
    return std.fmt.allocPrint(alloc, "{d}%", .{pct});
}

// Format the exact count of unique non-empty visible values in a column.
fn formatUniq(alloc: std.mem.Allocator, table: *Table, visible_col: usize) ![]u8 {
    var seen: std.StringHashMap(void) = .init(alloc);
    defer seen.deinit();

    for (0..table.nrows()) |visible_row| {
        const field = table.row(visible_row)[visible_col];
        if (field.len == 0) continue;
        try seen.put(field, {});
    }
    return std.fmt.allocPrint(alloc, "{d}", .{seen.count()});
}

// Format one visible column's minimum value using its inferred type.
fn formatMin(alloc: std.mem.Allocator, table: *Table, visible_col: usize) ![]u8 {
    return switch (table.column(visible_col).type) {
        .int => try formatIntEdge(alloc, table, visible_col, .min),
        .float => try formatFloatEdge(alloc, table, visible_col, .min),
        .string => try formatStringEdge(alloc, table, visible_col, .min),
    };
}

// Format one visible column's maximum value using its inferred type.
fn formatMax(alloc: std.mem.Allocator, table: *Table, visible_col: usize) ![]u8 {
    return switch (table.column(visible_col).type) {
        .int => try formatIntEdge(alloc, table, visible_col, .max),
        .float => try formatFloatEdge(alloc, table, visible_col, .max),
        .string => try formatStringEdge(alloc, table, visible_col, .max),
    };
}

// Pick the lower or upper edge of a visible column.
const Edge = enum { min, max };

// Format one integer edge for an inferred integer column.
fn formatIntEdge(alloc: std.mem.Allocator, table: *Table, visible_col: usize, edge: Edge) ![]u8 {
    var seen = false;
    var min_value: i64 = 0;
    var max_value: i64 = 0;
    var min_text: []const u8 = "";
    var max_text: []const u8 = "";

    for (0..table.nrows()) |visible_row| {
        const field = table.row(visible_row)[visible_col];
        if (field.len == 0) continue;
        const value = std.fmt.parseInt(i64, field, 10) catch continue;
        if (!seen or value < min_value) {
            min_value = value;
            min_text = field;
        }
        if (!seen or value > max_value) {
            max_value = value;
            max_text = field;
        }
        seen = true;
    }

    if (!seen) return alloc.dupe(u8, dash);
    return alloc.dupe(u8, if (edge == .min) min_text else max_text);
}

// Format one float edge for an inferred float column.
fn formatFloatEdge(alloc: std.mem.Allocator, table: *Table, visible_col: usize, edge: Edge) ![]u8 {
    var seen = false;
    var min_value: f64 = 0;
    var max_value: f64 = 0;
    var min_text: []const u8 = "";
    var max_text: []const u8 = "";

    for (0..table.nrows()) |visible_row| {
        const field = table.row(visible_row)[visible_col];
        if (field.len == 0) continue;
        const value = std.fmt.parseFloat(f64, field) catch continue;
        if (!seen or value < min_value) {
            min_value = value;
            min_text = field;
        }
        if (!seen or value > max_value) {
            max_value = value;
            max_text = field;
        }
        seen = true;
    }

    if (!seen) return alloc.dupe(u8, dash);
    return float.floatFormat(alloc, if (edge == .min) min_text else max_text, 3);
}

// Format one string-length edge for one visible string column.
fn formatStringEdge(alloc: std.mem.Allocator, table: *Table, visible_col: usize, edge: Edge) ![]u8 {
    var seen = false;
    var min_len: usize = 0;
    var max_len: usize = 0;

    for (0..table.nrows()) |visible_row| {
        const field = table.row(visible_row)[visible_col];
        if (field.len == 0) continue;
        const len = doomicode.displayWidth(field);
        if (!seen or len < min_len) min_len = len;
        if (!seen or len > max_len) max_len = len;
        seen = true;
    }

    if (!seen) return alloc.dupe(u8, dash);
    const len = if (edge == .min) min_len else max_len;
    return std.fmt.allocPrint(alloc, "{d} {s}", .{ len, util.plural(len, "char", "chars") });
}

//
// testing
//

test "shapeTitle includes optional title and visible shape" {
    const titled = try shapeTitle(testing.allocator, "foo", 1234, 5);
    defer testing.allocator.free(titled);
    try testing.expectEqualStrings("foo (1,234 rows × 5 cols)", titled);

    const bare = try shapeTitle(testing.allocator, "", 3, 2);
    defer testing.allocator.free(bare);
    try testing.expectEqualStrings("3 rows × 2 cols", bare);

    const singular = try shapeTitle(testing.allocator, "", 1, 1);
    defer testing.allocator.free(singular);
    try testing.expectEqualStrings("1 row × 1 col", singular);
}

test "sampleFooter pluralizes row count" {
    const one = try sampleFooter(testing.allocator, 1);
    defer testing.allocator.free(one);
    try testing.expectEqualStrings("… 1 more row …", one);

    const many = try sampleFooter(testing.allocator, 12);
    defer testing.allocator.free(many);
    try testing.expectEqualStrings("… 12 more rows …", many);
}

test "buildStatsTable reports basic visible stats" {
    const table = try Table.initCsv(testing.allocator, .{}, "name,score,city\nalice,10,boston\nbob,20,\ncara,20,chicago\n");
    defer table.deinit();

    const stats = try buildStatsTable(testing.allocator, table);
    defer stats.deinit();

    try test_support.expectEqualRows(&.{ "column", "type", "fill", "uniq", "min", "max" }, stats.headers());
    try test_support.expectEqualRows(&.{ "name", "string", "100%", "3", "3 chars", "5 chars" }, stats.row(0));
    try test_support.expectEqualRows(&.{ "score", "int", "100%", "2", "10", "20" }, stats.row(1));
    try test_support.expectEqualRows(&.{ "city", "string", "67%", "2", "6 chars", "7 chars" }, stats.row(2));
}

test "buildStatsTable truncates float min and max to three digits" {
    const table = try Table.initCsv(testing.allocator, .{}, "score\n1.23456\n20.9999\n");
    defer table.deinit();

    const stats = try buildStatsTable(testing.allocator, table);
    defer stats.deinit();

    try test_support.expectEqualRows(&.{ "score", "float", "100%", "2", "1.234", "20.999" }, stats.row(0));
}

const Config = @import("types.zig").Config;
const DataRow = @import("data.zig").DataRow;
const doomicode = @import("doomicode.zig");
const Field = @import("types.zig").Field;
const float = @import("float.zig");
const int = @import("int.zig");
const std = @import("std");
const Table = @import("table.zig").Table;
const testing = std.testing;
const test_support = @import("test_support.zig");
const util = @import("util.zig");
const dash = "—";
