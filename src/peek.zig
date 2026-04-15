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
    return try Table.init(table.app, alloc, config, try cloneRows(alloc, table.headers(), rows, config.head));
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

    return try Table.init(table.app, alloc, try statsConfig(alloc, table.config), .{ .rows = try rows.toOwnedSlice(alloc) });
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
            const mm = try parseIntMinmax(alloc, fields.items);
            return .{
                .fill = fill,
                .uniq = uniq,
                .min = try fmtIntValue(alloc, if (mm) |value| value.min else null),
                .max = try fmtIntValue(alloc, if (mm) |value| value.max else null),
            };
        },
        .float => {
            var values: std.ArrayList(f64) = .empty;
            defer values.deinit(alloc);
            for (fields.items) |f| try values.append(alloc, try std.fmt.parseFloat(f64, f));
            const mm = util.minmax(f64, values.items);
            return .{
                .fill = fill,
                .uniq = uniq,
                .min = try fmtFloatValue(alloc, if (mm) |value| value.min else null),
                .max = try fmtFloatValue(alloc, if (mm) |value| value.max else null),
            };
        },
        .percent => {
            var values: std.ArrayList(f64) = .empty;
            defer values.deinit(alloc);
            for (fields.items) |f| try values.append(alloc, try std.fmt.parseFloat(f64, f[0 .. f.len - 1]));
            const mm = util.minmax(f64, values.items);
            return .{
                .fill = fill,
                .uniq = uniq,
                .min = try fmtPercentValue(alloc, if (mm) |value| value.min else null),
                .max = try fmtPercentValue(alloc, if (mm) |value| value.max else null),
            };
        },
        .string => {
            var values: std.ArrayList(usize) = .empty;
            defer values.deinit(alloc);
            for (fields.items) |f| try values.append(alloc, f.len);
            const mm = util.minmax(usize, values.items);
            return .{
                .fill = fill,
                .uniq = uniq,
                .min = try fmtLenValue(alloc, if (mm) |value| value.min else null),
                .max = try fmtLenValue(alloc, if (mm) |value| value.max else null),
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

// Parse integer fields into i64 stats, returning null when any value overflows i64.
fn parseIntMinmax(alloc: std.mem.Allocator, fields: []const Field) !?struct { min: i64, max: i64 } {
    var values: std.ArrayList(i64) = .empty;
    defer values.deinit(alloc);
    for (fields) |field| {
        const value = std.fmt.parseInt(i64, field, 10) catch continue;
        try values.append(alloc, value);
    }
    if (util.minmax(i64, values.items)) |mm| return .{ .min = mm.min, .max = mm.max };
    return null;
}

fn fmtIntValue(alloc: std.mem.Allocator, value: ?i64) ![]u8 {
    const num = value orelse return alloc.dupe(u8, dash);
    var buf: [32]u8 = undefined;
    const raw = try std.fmt.bufPrint(&buf, "{d}", .{num});
    return int.intFormat(alloc, raw);
}

fn fmtFloatValue(alloc: std.mem.Allocator, value: ?f64) ![]u8 {
    const num = value orelse return alloc.dupe(u8, dash);
    const raw = try std.fmt.allocPrint(alloc, "{d}", .{num});
    defer alloc.free(raw);
    return float.floatFormat(alloc, raw, 3);
}

fn fmtLenValue(alloc: std.mem.Allocator, value: ?usize) ![]u8 {
    const len = value orelse return alloc.dupe(u8, dash);
    return std.fmt.allocPrint(alloc, "{d} {s}", .{ len, util.plural(len, "char") });
}

// Format percent min/max stats using the existing float formatter plus '%'.
fn fmtPercentValue(alloc: std.mem.Allocator, value: ?f64) ![]u8 {
    const formatted = try fmtFloatValue(alloc, value);
    defer alloc.free(formatted);
    if (std.mem.eql(u8, formatted, dash)) return alloc.dupe(u8, dash);
    return std.fmt.allocPrint(alloc, "{s}%", .{formatted});
}

//
// testing
//

test "sampleTitle includes optional title and visible shape" {
    var config: Config = .{ .title = try testing.allocator.dupe(u8, "foo") };
    defer config.deinit(testing.allocator);
    var titled_tt = try test_support.initTable(testing.allocator, config, "a,b\nc,d\n");
    defer titled_tt.deinit();
    const titled_table = titled_tt.table;
    const titled = try sampleTitle(testing.allocator, titled_table);
    defer testing.allocator.free(titled);
    try testing.expectEqualStrings("foo (1 row × 2 cols)", titled);

    var bare_tt = try test_support.initTable(testing.allocator, .{}, "a,b\nc,d\ne,f\ng,h\n");
    defer bare_tt.deinit();
    const bare_table = bare_tt.table;
    const bare = try sampleTitle(testing.allocator, bare_table);
    defer testing.allocator.free(bare);
    try testing.expectEqualStrings("3 rows × 2 cols", bare);

    var singular_tt = try test_support.initTable(testing.allocator, .{}, "a\nx\n");
    defer singular_tt.deinit();
    const singular_table = singular_tt.table;
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
    var tt = try test_support.initTable(testing.allocator, .{}, "name,score,city\nalice,10,boston\nbob,20,\ncara,20,chicago\n");
    defer tt.deinit();
    const table = tt.table;

    const stats = try buildStatsTable(testing.allocator, table);
    defer stats.deinit();

    try test_support.expectEqualRows(&.{ "column", "type", "fill", "uniq", "min", "max" }, stats.headers());
    try test_support.expectEqualRows(&.{ "name", "string", "100%", "3", "3 chars", "5 chars" }, stats.row(0));
    try test_support.expectEqualRows(&.{ "score", "int", "100%", "2", "10", "20" }, stats.row(1));
    try test_support.expectEqualRows(&.{ "city", "string", "66%", "2", "6 chars", "7 chars" }, stats.row(2));
}

test "buildStatsTable tolerates oversized ints in peek stats" {
    var tt = try test_support.initTable(testing.allocator, .{}, "id\n99999999999999999999\n");
    defer tt.deinit();
    const table = tt.table;

    const stats = try buildStatsTable(testing.allocator, table);
    defer stats.deinit();

    try testing.expectEqualStrings("id", stats.row(0)[0]);
    try testing.expectEqualStrings("int", stats.row(0)[1]);
    try testing.expectEqualStrings("—", stats.row(0)[4]);
    try testing.expectEqualStrings("—", stats.row(0)[5]);
}

test "buildStatsTable truncates float min and max to three digits" {
    var tt = try test_support.initTable(testing.allocator, .{}, "score\n1.23456\n20.9999\n");
    defer tt.deinit();
    const table = tt.table;

    const stats = try buildStatsTable(testing.allocator, table);
    defer stats.deinit();

    try test_support.expectEqualRows(&.{ "score", "float", "100%", "2", "1.234", "20.999" }, stats.row(0));
}

test "buildStatsTable treats percent columns as numeric" {
    var tt = try test_support.initTable(testing.allocator, .{}, "score,other\n12%,x\n-3.5%,y\n,z\n");
    defer tt.deinit();
    const table = tt.table;

    const stats = try buildStatsTable(testing.allocator, table);
    defer stats.deinit();

    try test_support.expectEqualRows(&.{ "score", "percent", "66%", "2", "-3.500%", "12.000%" }, stats.row(0));
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
