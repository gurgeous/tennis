// sqlite loader using the external sqlite3 CLI.

// Load one sqlite database file by selecting a table and decoding sqlite3 CSV output.
pub fn load(alloc: std.mem.Allocator, path: []const u8, selected_table: []const u8) !Data {
    const table = try chooseTable(alloc, path, selected_table);
    defer alloc.free(table);

    const ident = try util.quoteSql(alloc, table, '"');
    defer alloc.free(ident);

    const sql = try std.fmt.allocPrint(alloc, "SELECT * FROM {s};", .{ident});
    defer alloc.free(sql);

    const out = try runSqlite(alloc, &.{ "sqlite3", "-readonly", "-header", "-csv", path, sql });
    defer alloc.free(out.stderr);
    defer alloc.free(out.stdout);

    return try csv.load(alloc, out.stdout, ',');
}

// Choose a deterministic table, preferring the requested table or the largest table.
fn chooseTable(alloc: std.mem.Allocator, path: []const u8, selected_table: []const u8) ![]u8 {
    if (selected_table.len > 0) return try pickRequestedTable(alloc, path, selected_table);
    if (try hasDbstat(alloc, path)) return try queryScalar(alloc, path, largestTableSql);
    return try firstTable(alloc, path);
}

// Return the requested table when it exists, otherwise fail.
fn pickRequestedTable(alloc: std.mem.Allocator, path: []const u8, selected_table: []const u8) ![]u8 {
    const value = try util.quoteSql(alloc, selected_table, '\'');
    defer alloc.free(value);

    const sql = try std.fmt.allocPrint(alloc, "SELECT name FROM pragma_table_list WHERE schema = 'main' AND type = 'table' AND name = {s} LIMIT 1;", .{value});
    defer alloc.free(sql);

    return queryScalar(alloc, path, sql) catch |err| switch (err) {
        error.SqliteNoTables => error.SqliteInvalidTable,
        else => err,
    };
}

// Return the first ordinary user table by name.
fn firstTable(alloc: std.mem.Allocator, path: []const u8) ![]u8 {
    const tables = try listTables(alloc, path);
    defer freeTables(alloc, tables);
    if (tables.len == 0) return error.SqliteNoTables;
    return alloc.dupe(u8, tables[0]);
}

// Report whether the local sqlite3 build exposes dbstat.
fn hasDbstat(alloc: std.mem.Allocator, path: []const u8) !bool {
    const result = try runSqlite(alloc, &.{
        "sqlite3",
        "-readonly",
        "-batch",
        "-noheader",
        path,
        "SELECT 1 FROM pragma_compile_options WHERE compile_options = 'ENABLE_DBSTAT_VTAB' LIMIT 1;",
    });
    defer alloc.free(result.stderr);
    defer alloc.free(result.stdout);

    switch (result.term) {
        .Exited => |code| if (code != 0) return error.SqliteCliFailed,
        else => return error.SqliteCliFailed,
    }

    return util.strip(u8, result.stdout).len > 0;
}

// Run a scalar SQL query and return the trimmed first line.
fn queryScalar(alloc: std.mem.Allocator, path: []const u8, sql: []const u8) ![]u8 {
    const result = try runSqlite(alloc, &.{ "sqlite3", "-readonly", "-batch", "-noheader", path, sql });
    defer alloc.free(result.stderr);
    defer alloc.free(result.stdout);

    switch (result.term) {
        .Exited => |code| {
            if (code != 0) return error.SqliteCliFailed;
        },
        else => return error.SqliteCliFailed,
    }

    const trimmed = util.strip(u8, result.stdout);
    if (trimmed.len == 0) return error.SqliteNoTables;
    return alloc.dupe(u8, trimmed);
}

// Execute sqlite3 and capture stdout/stderr for later inspection.
fn runSqlite(alloc: std.mem.Allocator, argv: []const []const u8) !std.process.Child.RunResult {
    return std.process.Child.run(.{
        .allocator = alloc,
        .argv = argv,
        .max_output_bytes = 64 * 1024 * 1024,
    }) catch |err| switch (err) {
        error.FileNotFound => error.SqliteCliMissing,
        error.StdoutStreamTooLong, error.StderrStreamTooLong => error.SqliteTooLarge,
        else => err,
    };
}

// List ordinary user tables in the main sqlite schema.
pub fn listTables(alloc: std.mem.Allocator, path: []const u8) ![][]const u8 {
    const result = try runSqlite(alloc, &.{ "sqlite3", "-readonly", "-batch", "-noheader", path, listTablesSql });
    defer alloc.free(result.stderr);
    defer alloc.free(result.stdout);

    switch (result.term) {
        .Exited => |code| if (code != 0) return error.SqliteCliFailed,
        else => return error.SqliteCliFailed,
    }

    var out: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (out.items) |name| alloc.free(name);
        out.deinit(alloc);
    }

    var it = std.mem.tokenizeScalar(u8, result.stdout, '\n');
    while (it.next()) |line| {
        const name = util.strip(u8, line);
        if (name.len == 0) continue;
        try out.append(alloc, try alloc.dupe(u8, name));
    }

    return out.toOwnedSlice(alloc);
}

// Release the table-name list returned by listTables.
pub fn freeTables(alloc: std.mem.Allocator, tables: [][]const u8) void {
    for (tables) |name| alloc.free(name);
    alloc.free(tables);
}

//
// sql
//

const listTablesSql =
    \\SELECT name
    \\FROM pragma_table_list
    \\WHERE schema = 'main' AND type = 'table' AND name NOT LIKE 'sqlite_%'
    \\ORDER BY name;
;

const largestTableSql =
    \\SELECT name
    \\FROM (
    \\    SELECT tl.name AS name, COALESCE(SUM(ds.pgsize), 0) AS total_size
    \\    FROM pragma_table_list AS tl
    \\    LEFT JOIN dbstat AS ds ON ds.name = tl.name
    \\    WHERE tl.schema = 'main' AND tl.type = 'table' AND tl.name NOT LIKE 'sqlite_%'
    \\    GROUP BY tl.name
    \\)
    \\ORDER BY total_size DESC, name ASC
    \\LIMIT 1;
;

//
// testing
//

test "table selection queries are deterministic" {
    const cases = [_]struct {
        sql: []const u8,
        want: []const []const u8,
    }{
        .{ .sql = listTablesSql, .want = &.{ "pragma_table_list", "order by name" } },
        .{ .sql = largestTableSql, .want = &.{ "pragma_table_list", "order by total_size desc, name asc" } },
    };

    for (cases) |tc| {
        for (tc.want) |needle| {
            try testing.expect(util.containsIgnoreCase(tc.sql, needle));
        }
    }
}

const csv = @import("csv.zig");
const Data = @import("data.zig").Data;
const std = @import("std");
const testing = std.testing;
const util = @import("util.zig");
