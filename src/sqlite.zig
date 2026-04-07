// sqlite loader using the external sqlite3 CLI.

// One opened sqlite file plus cached metadata used for selection and errors.
pub const Sqlite = struct {
    alloc: std.mem.Allocator,
    path: []const u8,
    tables: [][]const u8,
    has_dbstat: bool,

    const Self = @This();

    // Initialize sqlite metadata for one file.
    pub fn init(alloc: std.mem.Allocator, path: []const u8) !Self {
        const tables = try listTablesAlloc(alloc, path);
        errdefer freeTableNames(alloc, tables);
        return .{
            .alloc = alloc,
            .path = path,
            .tables = tables,
            .has_dbstat = try hasDbstat(alloc, path),
        };
    }

    // Release cached table metadata.
    pub fn deinit(self: Self) void {
        freeTableNames(self.alloc, self.tables);
    }

    // Load data from the requested or inferred table.
    pub fn load(self: Self, selected_table: []const u8) !Data {
        const table_unq = try self.chooseTable(selected_table);
        defer self.alloc.free(table_unq);
        const table = try util.quoteSql(self.alloc, table_unq, '"');
        defer self.alloc.free(table);

        const sql = try std.fmt.allocPrint(self.alloc, "SELECT * FROM {s};", .{table});
        defer self.alloc.free(sql);

        const out = try runSqlite(self.alloc, &.{ "sqlite3", "-readonly", "-header", "-csv", self.path, sql });
        defer self.alloc.free(out.stderr);
        defer self.alloc.free(out.stdout);

        return try csv.load(self.alloc, out.stdout, ',');
    }

    // Return the cached ordinary user tables.
    pub fn listTables(self: Self) []const []const u8 {
        return self.tables;
    }

    // Choose a deterministic table, preferring the requested table or the largest table.
    fn chooseTable(self: Self, selected_table: []const u8) ![]u8 {
        if (selected_table.len > 0) return try self.pickRequestedTable(selected_table);
        if (self.has_dbstat) return try queryScalar(self.alloc, self.path, largestTableSql);
        return try self.firstTable();
    }

    // Return the requested table when it exists, otherwise fail.
    fn pickRequestedTable(self: Self, selected_table: []const u8) ![]u8 {
        for (self.tables) |table| {
            if (std.mem.eql(u8, table, selected_table)) return self.alloc.dupe(u8, table);
        }
        return error.SqliteInvalidTable;
    }

    // Return the first ordinary user table by name.
    fn firstTable(self: Self) ![]u8 {
        if (self.tables.len == 0) return error.SqliteNoTables;
        return self.alloc.dupe(u8, self.tables[0]);
    }
};

// Run one sqlite query and return owned stdout bytes after checking the exit status.
fn runSql(alloc: std.mem.Allocator, path: []const u8, sql: []const u8) ![]u8 {
    const result = try runSqlite(alloc, &.{ "sqlite3", "-readonly", "-batch", "-noheader", path, sql });
    defer alloc.free(result.stderr);

    switch (result.term) {
        .Exited => |code| {
            if (code != 0) {
                alloc.free(result.stdout);
                return error.SqliteCliFailed;
            }
        },
        else => {
            alloc.free(result.stdout);
            return error.SqliteCliFailed;
        },
    }

    return result.stdout;
}

// Run a scalar sql query and return the trimmed first line.
fn queryScalar(alloc: std.mem.Allocator, path: []const u8, sql: []const u8) ![]u8 {
    const value = try queryScalarOrNull(alloc, path, sql);
    return value orelse error.SqliteNoTables;
}

// Run a scalar sql query and return the trimmed first line or null.
fn queryScalarOrNull(alloc: std.mem.Allocator, path: []const u8, sql: []const u8) !?[]u8 {
    const stdout = try runSql(alloc, path, sql);
    defer alloc.free(stdout);

    const trimmed = util.strip(u8, stdout);
    if (trimmed.len == 0) return null;
    return try alloc.dupe(u8, trimmed);
}

// Report whether the local sqlite3 build exposes dbstat.
fn hasDbstat(alloc: std.mem.Allocator, path: []const u8) !bool {
    const value = try queryScalarOrNull(alloc, path, "SELECT 1 FROM pragma_compile_options WHERE compile_options = 'ENABLE_DBSTAT_VTAB' LIMIT 1;");
    defer if (value) |v| alloc.free(v);
    return value != null;
}

// List ordinary user tables in the main sqlite schema.
fn listTablesAlloc(alloc: std.mem.Allocator, path: []const u8) ![][]const u8 {
    const stdout = try runSql(alloc, path, listTablesSql);
    defer alloc.free(stdout);

    var out: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (out.items) |name| alloc.free(name);
        out.deinit(alloc);
    }

    var it = std.mem.tokenizeScalar(u8, stdout, '\n');
    while (it.next()) |line| {
        const name = util.strip(u8, line);
        if (name.len == 0) continue;
        try out.append(alloc, try alloc.dupe(u8, name));
    }

    return out.toOwnedSlice(alloc);
}

// Release owned table names.
fn freeTableNames(alloc: std.mem.Allocator, tables: [][]const u8) void {
    for (tables) |name| alloc.free(name);
    alloc.free(tables);
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
