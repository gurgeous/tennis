// Build and render a compact sample + stats view for one visible table.
pub fn render(alloc: std.mem.Allocator, table: *Table, writer: *std.Io.Writer) !void {
    // sample
    const sample = try buildSampleTable(alloc, table);
    defer sample.deinit();
    try sample.renderTable(writer);
    try writer.writeByte('\n');

    // stats
    const stats = try buildStatsTable(alloc, table);
    defer stats.deinit();
    try stats.renderTable(writer);
}

//
// sample
//

// Build a small visible-row sample table with shape embedded in the title.
fn buildSampleTable(alloc: std.mem.Allocator, table: *Table) !*Table {
    var config = sampleConfig(table.config);
    config.title = try sampleTitle(alloc, table);

    config.head = 5;
    const n = @min(config.head, table.nrows());
    if (table.nrows() > n) {
        config.footer = try sampleFooter(alloc, table.nrows() - n);
    }
    const rows = try alloc.alloc(Row, table.nrows());
    defer alloc.free(rows);
    for (rows, 0..) |*row, ii| row.* = table.row(ii);
    return try Table.init(alloc, config, try cloneRows(alloc, table.headers(), rows, config.head));
}

// Derive a config for the sample table without reapplying row/col transforms.
fn sampleConfig(c: Config) Config {
    return .{ .border = c.border, .color = c.color, .theme = c.theme, .width = c.width };
}

// Format the sample/stats title with the current visible shape.
fn sampleTitle(alloc: std.mem.Allocator, table: *Table) ![]u8 {
    const rows = try util.pluralCount(alloc, table.nrows(), "row");
    defer alloc.free(rows);
    const cols = try util.pluralCount(alloc, table.ncols(), "col");
    defer alloc.free(cols);

    if (table.config.title.len > 0) {
        return std.fmt.allocPrint(alloc, "{s} ({s} × {s})", .{ table.config.title, rows, cols });
    }
    return std.fmt.allocPrint(alloc, "{s} × {s}", .{ rows, cols });
}

// Format the centered sample footer when the sample omits visible rows.
fn sampleFooter(alloc: std.mem.Allocator, nmore: usize) ![]u8 {
    const more = try util.pluralCount(alloc, nmore, "more row");
    defer alloc.free(more);
    return std.fmt.allocPrint(alloc, "… {s} …", .{more});
}

//
// stats
//

// Build one visible-column stats table for the current visible table.
fn buildStatsTable(alloc: std.mem.Allocator, table: *Table) !*Table {
    const headers = [_]Field{ "column", "type", "fill", "uniq", "min", "max" };
    var rows: std.ArrayList(DataRow) = .empty;
    defer {
        for (rows.items) |row| row.deinit(alloc);
        rows.deinit(alloc);
    }
    try rows.append(alloc, try DataRow.init(alloc, &headers));
    for (0..table.ncols()) |ii| try rows.append(alloc, try buildStatsRow(alloc, table, ii));

    return try Table.init(alloc, try statsConfig(alloc, table.config), .{ .rows = try rows.toOwnedSlice(alloc) });
}

// Build one owned stats row for one visible column.
fn buildStatsRow(alloc: std.mem.Allocator, table: *Table, c: usize) !DataRow {
    const column = table.column(c);
    const s = try columnStats(alloc, table, c, column.type);
    defer s.deinit(alloc);
    const row = [_]Field{ table.headers()[c], @tagName(column.type), s.fill, s.uniq, s.min, s.max };
    return try DataRow.init(alloc, &row);
}

// Derive a config for the stats table.
fn statsConfig(alloc: std.mem.Allocator, config: Config) !Config {
    var out = sampleConfig(config);
    out.row_numbers = false;
    out.title = try alloc.dupe(u8, "stats");
    return out;
}

const dash = "—";

const Edge = enum { min, max };

const Stats = struct {
    fill: []u8,
    uniq: []u8,
    min: []u8,
    max: []u8,

    fn deinit(self: Stats, alloc: std.mem.Allocator) void {
        alloc.free(self.fill);
        alloc.free(self.uniq);
        alloc.free(self.min);
        alloc.free(self.max);
    }
};

fn columnStats(alloc: std.mem.Allocator, table: *Table, c: usize, t: ColumnType) !Stats {
    // non-empty values
    var fields: std.ArrayList(Field) = .empty;
    defer fields.deinit(alloc);

    // unique values
    var seen: std.StringHashMap(void) = .init(alloc);
    defer seen.deinit();

    for (0..table.nrows()) |r| {
        const field = table.row(r)[c];
        if (field.len == 0) continue;
        try fields.append(alloc, field);
        try seen.put(field, {});
    }

    const fill = try fmtFill(alloc, fields.items.len, table.nrows());
    const uniq = try std.fmt.allocPrint(alloc, "{d}", .{seen.count()});

    switch (t) {
        .int => {
            var values: std.ArrayList(i64) = .empty;
            defer values.deinit(alloc);
            for (fields.items) |f| try values.append(alloc, try std.fmt.parseInt(i64, f, 10));
            return .{
                .fill = fill,
                .uniq = uniq,
                .min = try fmtInt(alloc, values.items, .min),
                .max = try fmtInt(alloc, values.items, .max),
            };
        },
        .float => {
            var values: std.ArrayList(f64) = .empty;
            defer values.deinit(alloc);
            for (fields.items) |f| try values.append(alloc, try std.fmt.parseFloat(f64, f));
            return .{
                .fill = fill,
                .uniq = uniq,
                .min = try fmtFloat(alloc, values.items, .min),
                .max = try fmtFloat(alloc, values.items, .max),
            };
        },
        .string => {
            var values: std.ArrayList(usize) = .empty;
            defer values.deinit(alloc);
            for (fields.items) |f| try values.append(alloc, f.len);
            return .{
                .fill = fill,
                .uniq = uniq,
                .min = try fmtLen(alloc, values.items, .min),
                .max = try fmtLen(alloc, values.items, .max),
            };
        },
    }
}

//
// stats helpers
//

fn fmtFill(alloc: std.mem.Allocator, fill: usize, nrows: usize) ![]u8 {
    if (nrows == 0) return alloc.dupe(u8, "0%");
    const pct = (fill * 100 / nrows);
    return std.fmt.allocPrint(alloc, "{d}%", .{pct});
}

fn fmtInt(alloc: std.mem.Allocator, values: []const i64, edge: Edge) ![]u8 {
    const mm = util.minmax(i64, values) orelse return alloc.dupe(u8, dash);
    var buf: [32]u8 = undefined;
    const raw = try std.fmt.bufPrint(&buf, "{d}", .{if (edge == .min) mm.min else mm.max});
    return int.intFormat(alloc, raw);
}

fn fmtFloat(alloc: std.mem.Allocator, values: []const f64, edge: Edge) ![]u8 {
    const mm = util.minmax(f64, values) orelse return alloc.dupe(u8, dash);
    const raw = try std.fmt.allocPrint(alloc, "{d}", .{if (edge == .min) mm.min else mm.max});
    defer alloc.free(raw);
    return float.floatFormat(alloc, raw, 3);
}

fn fmtLen(alloc: std.mem.Allocator, lens: []const usize, edge: Edge) ![]u8 {
    const mm = util.minmax(usize, lens) orelse return alloc.dupe(u8, dash);
    const len = if (edge == .min) mm.min else mm.max;
    return std.fmt.allocPrint(alloc, "{d} {s}", .{ len, util.plural(len, "char") });
}

//
// testing
//

test "sampleTitle includes optional title and visible shape" {
    var config: Config = .{ .title = try testing.allocator.dupe(u8, "foo") };
    defer config.deinit(testing.allocator);
    const titled_table = try Table.initCsv(testing.allocator, config, "a,b\nc,d\n");
    defer titled_table.deinit();
    const titled = try sampleTitle(testing.allocator, titled_table);
    defer testing.allocator.free(titled);
    try testing.expectEqualStrings("foo (1 row × 2 cols)", titled);

    const bare_table = try Table.initCsv(testing.allocator, .{}, "a,b\nc,d\ne,f\ng,h\n");
    defer bare_table.deinit();
    const bare = try sampleTitle(testing.allocator, bare_table);
    defer testing.allocator.free(bare);
    try testing.expectEqualStrings("3 rows × 2 cols", bare);

    const singular_table = try Table.initCsv(testing.allocator, .{}, "a\nx\n");
    defer singular_table.deinit();
    const singular = try sampleTitle(testing.allocator, singular_table);
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
    try test_support.expectEqualRows(&.{ "city", "string", "66%", "2", "6 chars", "7 chars" }, stats.row(2));
}

test "buildStatsTable truncates float min and max to three digits" {
    const table = try Table.initCsv(testing.allocator, .{}, "score\n1.23456\n20.9999\n");
    defer table.deinit();

    const stats = try buildStatsTable(testing.allocator, table);
    defer stats.deinit();

    try test_support.expectEqualRows(&.{ "score", "float", "100%", "2", "1.234", "20.999" }, stats.row(0));
}

const cloneRows = @import("data.zig").cloneRows;
const ColumnType = @import("column.zig").ColumnType;
const Config = @import("types.zig").Config;
const DataRow = @import("data.zig").DataRow;
const doomicode = @import("doomicode.zig");
const Field = @import("types.zig").Field;
const float = @import("float.zig");
const int = @import("int.zig");
const Row = @import("types.zig").Row;
const std = @import("std");
const Table = @import("table.zig").Table;
const testing = std.testing;
const test_support = @import("test_support.zig");
const util = @import("util.zig");
