// Small helpers for unit tests that need an owned Table.

// Assert that two string slices match element by element.
pub fn expectEqualRows(want: []const []const u8, got: []const []const u8) !void {
    try testing.expectEqual(want.len, got.len);
    for (want, got) |w, g| try testing.expectEqualStrings(w, g);
}

// Small owned-table harness used by unit tests.
pub const TestTable = struct {
    app: *App = undefined,
    table: *Table = undefined,

    // Build a test table from an inline CSV string.
    pub fn init(self: *TestTable, alloc: std.mem.Allocator, config: types.Config, input: []const u8) !void {
        self.app = try App.testInit(alloc);
        errdefer self.app.destroy();
        self.table = try Table.initCsv(self.app, config, input);
    }

    // Release the arena and test table.
    pub fn deinit(self: *TestTable) void {
        self.table.deinit();
        self.app.destroy();
    }
};

// Build one owned test table and return the harness by value.
pub fn initTable(alloc: std.mem.Allocator, config: types.Config, input: []const u8) !TestTable {
    var out: TestTable = .{};
    try out.init(alloc, config, input);
    return out;
}

const App = @import("app.zig").App;
const std = @import("std");
const testing = std.testing;
const Table = @import("table.zig").Table;
const types = @import("types.zig");
