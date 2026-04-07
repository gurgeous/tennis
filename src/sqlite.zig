// SQLite loader using the external sqlite3 CLI.

// Load one SQLite database file by selecting a table and decoding sqlite3 CSV output.
pub fn load(alloc: std.mem.Allocator, path: []const u8) !Data {
    const table = try chooseTable(alloc, path);
    defer alloc.free(table);

    const ident = try quoteIdentifier(alloc, table);
    defer alloc.free(ident);

    const sql = try std.fmt.allocPrint(alloc, "SELECT * FROM {s};", .{ident});
    defer alloc.free(sql);

    const out = try runSqlite(alloc, &.{ "sqlite3", "-readonly", "-header", "-csv", path, sql });
    defer alloc.free(out.stderr);
    defer alloc.free(out.stdout);

    return try csv.load(alloc, out.stdout, ',');
}

// Choose a deterministic table, preferring the largest one when dbstat is available.
fn chooseTable(alloc: std.mem.Allocator, path: []const u8) ![]u8 {
    return queryScalar(alloc, path, largestTableSql) catch |err| switch (err) {
        error.SqliteDbstatUnavailable => try queryScalar(alloc, path, firstTableSql),
        else => err,
    };
}

// Run a scalar SQL query and return the trimmed first line.
fn queryScalar(alloc: std.mem.Allocator, path: []const u8, sql: []const u8) ![]u8 {
    const result = try runSqlite(alloc, &.{ "sqlite3", "-readonly", "-batch", "-noheader", path, sql });
    defer alloc.free(result.stderr);
    defer alloc.free(result.stdout);

    switch (result.term) {
        .Exited => |code| {
            if (code != 0) {
                if (util.containsIgnoreCase(result.stderr, "no such table: dbstat")) return error.SqliteDbstatUnavailable;
                return error.SqliteCliFailed;
            }
        },
        else => return error.SqliteCliFailed,
    }

    const trimmed = util.strip(u8, result.stdout);
    if (trimmed.len == 0) return error.SqliteNoTables;
    return alloc.dupe(u8, trimmed);
}

// Escape one SQLite identifier using double-quoted identifier syntax.
fn quoteIdentifier(alloc: std.mem.Allocator, ident: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(alloc);

    try out.append(alloc, '"');
    for (ident) |ch| {
        if (ch == '"') try out.append(alloc, '"');
        try out.append(alloc, ch);
    }
    try out.append(alloc, '"');
    return out.toOwnedSlice(alloc);
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

//
// testing
//

test "quoteIdentifier escapes embedded quotes" {
    const got = try quoteIdentifier(testing.allocator, "weird\"name");
    defer testing.allocator.free(got);
    try testing.expectEqualStrings("\"weird\"\"name\"", got);
}

test "largest table query is deterministic" {
    try testing.expect(util.containsIgnoreCase(largestTableSql, "pragma_table_list"));
    try testing.expect(util.containsIgnoreCase(largestTableSql, "order by total_size desc, name asc"));
    try testing.expect(util.containsIgnoreCase(firstTableSql, "order by name"));
}

const firstTableSql =
    \\SELECT name
    \\FROM pragma_table_list
    \\WHERE schema = 'main' AND type = 'table' AND name NOT LIKE 'sqlite_%'
    \\ORDER BY name
    \\LIMIT 1;
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

const csv = @import("csv.zig");
const Data = @import("data.zig").Data;
const std = @import("std");
const testing = std.testing;
const util = @import("util.zig");
