// sqlite loader using the external sqlite3 CLI.

// One opened sqlite file plus cached metadata used for selection and errors.
pub const Sqlite = struct {
    app: *App,
    path: []const u8,
    tables: [][]const u8,

    const Self = @This();

    // Initialize sqlite metadata for one file.
    pub fn init(app: *App, path: []const u8) !Self {
        return .{
            .app = app,
            .path = path,
            .tables = try listTablesAlloc(app, path),
        };
    }

    // Release cached table metadata.
    pub fn deinit(self: Self) void {
        for (self.tables) |name| self.app.alloc.free(name);
        self.app.alloc.free(self.tables);
    }

    // Load data from the requested or inferred table.
    pub fn load(self: *Self, selected_table: []const u8) !Data {
        const table_unq = try self.chooseTable(selected_table);
        defer self.app.alloc.free(table_unq);
        const table = try util.quoteSql(self.app.alloc, table_unq, '"');
        defer self.app.alloc.free(table);

        const sql = try std.fmt.allocPrint(self.app.alloc, "SELECT * FROM {s};", .{table});
        defer self.app.alloc.free(sql);

        const stdout = try runSqlCsv(self.app, self.path, sql);
        defer self.app.alloc.free(stdout);

        return try csv.load(self.app, stdout, ',');
    }

    // Choose a deterministic table, preferring the requested table or the largest table.
    fn chooseTable(self: *Self, selected_table: []const u8) ![]u8 {
        // do we have any tables?
        if (self.tables.len == 0) return error.SqliteNoTables;

        // --table
        if (selected_table.len > 0) {
            for (self.tables) |table| {
                if (std.ascii.eqlIgnoreCase(table, selected_table)) {
                    return self.app.alloc.dupe(u8, table);
                }
            }
            return error.SqliteInvalidTable;
        }

        // largest table via dbstat, if available
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
        if (try self.hasDbstat()) return try queryScalar(self.app, self.path, largestTableSql);

        // just the first able, I guess
        return self.app.alloc.dupe(u8, self.tables[0]);
    }

    // Report whether the local sqlite3 has dbstat
    fn hasDbstat(self: *Self) !bool {
        const sql =
            \\SELECT 1 FROM dbstat LIMIT 1;
        ;
        const value = queryScalarOrNull(self.app, self.path, sql) catch |err| switch (err) {
            error.SqliteCliFailed => return false,
            else => return err,
        };
        defer if (value) |v| self.app.alloc.free(v);
        return true;
    }
};

// List tables
fn listTablesAlloc(app: *App, path: []const u8) ![][]const u8 {
    const sql =
        \\SELECT name
        \\FROM pragma_table_list
        \\WHERE schema = 'main' AND type = 'table' AND name NOT LIKE 'sqlite_%'
        \\ORDER BY name;
    ;

    const stdout = try runSql(app, path, sql);
    defer app.alloc.free(stdout);

    var out: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (out.items) |name| app.alloc.free(name);
        out.deinit(app.alloc);
    }

    var it = std.mem.tokenizeScalar(u8, stdout, '\n');
    while (it.next()) |line| {
        const name = util.strip(u8, line);
        if (name.len == 0) continue;
        try out.append(app.alloc, try app.alloc.dupe(u8, name));
    }

    return out.toOwnedSlice(app.alloc);
}

// Run one query and return bytes.
fn runSql(app: *App, path: []const u8, sql: []const u8) ![]u8 {
    return runSqlWithArgs(app, &.{ "-batch", "-noheader", path, sql });
}

// Run one csv query and return bytes.
fn runSqlCsv(app: *App, path: []const u8, sql: []const u8) ![]u8 {
    return runSqlWithArgs(app, &.{ "-batch", "-header", "-csv", path, sql });
}

// Run one sqlite command with fixed argv and return stdout on success.
fn runSqlWithArgs(app: *App, argv: []const []const u8) ![]u8 {
    const result = try runSqlite(app, argv);
    defer app.alloc.free(result.stderr);

    switch (result.term) {
        .exited => |code| {
            if (code != 0) {
                app.alloc.free(result.stdout);
                return error.SqliteCliFailed;
            }
        },
        else => {
            app.alloc.free(result.stdout);
            return error.SqliteCliFailed;
        },
    }

    return result.stdout;
}

// Run a scalar sql query and return first line
fn queryScalar(app: *App, path: []const u8, sql: []const u8) ![]u8 {
    const value = try queryScalarOrNull(app, path, sql);
    return value orelse error.SqliteNoTables;
}

// Run a scalar sql query and return first line or null.
fn queryScalarOrNull(app: *App, path: []const u8, sql: []const u8) !?[]u8 {
    const stdout = try runSql(app, path, sql);
    defer app.alloc.free(stdout);

    const trimmed = util.strip(u8, stdout);
    if (trimmed.len == 0) return null;
    return try app.alloc.dupe(u8, trimmed);
}

// Run a single sqlite command
fn runSqlite(app: *App, argv_in: []const []const u8) !std.process.RunResult {
    // SQLite export can legitimately be large for wide tables.
    const max_output_bytes = 64 * 1024 * 1024;
    const argv = try std.mem.concat(app.alloc, []const u8, &.{ &.{ "sqlite3", "-readonly" }, argv_in });
    defer app.alloc.free(argv);

    return std.process.run(app.alloc, app.io, .{
        .argv = argv,
        .stdout_limit = .limited(max_output_bytes),
        .stderr_limit = .limited(max_output_bytes),
    }) catch |err| switch (err) {
        error.FileNotFound => error.SqliteCliMissing,
        error.StreamTooLong => error.SqliteTooLarge,
        else => err,
    };
}

const App = @import("app.zig").App;
const csv = @import("csv.zig");
const Data = @import("data.zig").Data;
const std = @import("std");
const util = @import("util.zig");
