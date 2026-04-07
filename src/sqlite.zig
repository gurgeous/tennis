// sqlite loader using the external sqlite3 CLI.

// One opened sqlite file plus cached metadata used for selection and errors.
pub const Sqlite = struct {
    alloc: std.mem.Allocator,
    path: []const u8,
    tables: [][]const u8,

    const Self = @This();

    // Initialize sqlite metadata for one file.
    pub fn init(alloc: std.mem.Allocator, path: []const u8) !Self {
        return .{
            .alloc = alloc,
            .path = path,
            .tables = try listTablesAlloc(alloc, path),
        };
    }

    // Release cached table metadata.
    pub fn deinit(self: Self) void {
        for (self.tables) |name| self.alloc.free(name);
        self.alloc.free(self.tables);
    }

    // Load data from the requested or inferred table.
    pub fn load(self: *Self, selected_table: []const u8) !Data {
        const table_unq = try self.chooseTable(selected_table);
        defer self.alloc.free(table_unq);
        const table = try util.quoteSql(self.alloc, table_unq, '"');
        defer self.alloc.free(table);

        const sql = try std.fmt.allocPrint(self.alloc, "SELECT * FROM {s};", .{table});
        defer self.alloc.free(sql);

        const out = try runSqlite(self.alloc, self.path, &.{ "-header", "-csv", self.path, sql });
        defer self.alloc.free(out.stderr);
        defer self.alloc.free(out.stdout);

        return try csv.load(self.alloc, out.stdout, ',');
    }

    // Choose a deterministic table, preferring the requested table or the largest table.
    fn chooseTable(self: *Self, selected_table: []const u8) ![]u8 {
        // do we have any tables?
        if (self.tables.len == 0) return error.SqliteNoTables;

        // --table
        if (selected_table.len > 0) {
            for (self.tables) |table| {
                if (std.mem.eql(u8, table, selected_table)) return self.alloc.dupe(u8, table);
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
        if (try self.hasDbstat()) return try queryScalar(self.alloc, self.path, largestTableSql);

        // just the first able, I guess
        return self.alloc.dupe(u8, self.tables[0]);
    }

    // Report whether the local sqlite3 has dbstat
    fn hasDbstat(self: *Self) !bool {
        const sql =
            \\SELECT 1 FROM dbstat LIMIT 1;
        ;
        const value = queryScalarOrNull(self.alloc, self.path, sql) catch |err| switch (err) {
            error.SqliteCliFailed => return false,
            else => return err,
        };
        defer if (value) |v| self.alloc.free(v);
        return true;
    }
};

// List tables
fn listTablesAlloc(alloc: std.mem.Allocator, path: []const u8) ![][]const u8 {
    const sql =
        \\SELECT name
        \\FROM pragma_table_list
        \\WHERE schema = 'main' AND type = 'table' AND name NOT LIKE 'sqlite_%'
        \\ORDER BY name;
    ;

    const stdout = try runSql(alloc, path, sql);
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

// Run one query and return bytes
fn runSql(alloc: std.mem.Allocator, path: []const u8, sql: []const u8) ![]u8 {
    util.tdebug("sqlite path={s}", .{path});
    util.tdebug("sqlite sql={s}", .{sql});

    const result = try runSqlite(alloc, path, &.{ "-batch", "-noheader", path, sql });
    defer alloc.free(result.stderr);

    switch (result.term) {
        .Exited => |code| {
            if (code != 0) {
                const stderr = util.strip(u8, result.stderr);
                const stdout = util.strip(u8, result.stdout);
                util.tdebug("sqlite exit={d}", .{code});
                if (stderr.len > 0) util.tdebug("sqlite stderr={s}", .{stderr});
                if (stdout.len > 0) util.tdebug("sqlite stdout={s}", .{stdout});
                alloc.free(result.stdout);
                return error.SqliteCliFailed;
            }
        },
        else => {
            util.tdebug("sqlite term={s}", .{@tagName(result.term)});
            alloc.free(result.stdout);
            return error.SqliteCliFailed;
        },
    }

    return result.stdout;
}

// Run a scalar sql query and return first line
fn queryScalar(alloc: std.mem.Allocator, path: []const u8, sql: []const u8) ![]u8 {
    const value = try queryScalarOrNull(alloc, path, sql);
    return value orelse error.SqliteNoTables;
}

// Run a scalar sql query and return first line or null.
fn queryScalarOrNull(alloc: std.mem.Allocator, path: []const u8, sql: []const u8) !?[]u8 {
    const stdout = try runSql(alloc, path, sql);
    defer alloc.free(stdout);

    const trimmed = util.strip(u8, stdout);
    if (trimmed.len == 0) return null;
    return try alloc.dupe(u8, trimmed);
}

// Run a single sqlite command
fn runSqlite(alloc: std.mem.Allocator, path: []const u8, argv_in: []const []const u8) !std.process.Child.RunResult {
    // SQLite export can legitimately be large for wide tables.
    const max_output_bytes = 64 * 1024 * 1024;
    const argv = try std.mem.concat(alloc, []const u8, &.{ &.{ "sqlite3", "-readonly" }, argv_in });
    defer alloc.free(argv);

    util.tdebug("sqlite argv=sqlite3 -readonly {s} ...", .{path});

    return std.process.Child.run(.{
        .allocator = alloc,
        .argv = argv,
        .max_output_bytes = max_output_bytes,
    }) catch |err| switch (err) {
        error.FileNotFound => error.SqliteCliMissing,
        error.StdoutStreamTooLong, error.StderrStreamTooLong => error.SqliteTooLarge,
        else => err,
    };
}

const csv = @import("csv.zig");
const Data = @import("data.zig").Data;
const std = @import("std");
const util = @import("util.zig");
