// Small helpers for unit tests that need an owned Table.

// Assert that two string slices match element by element.
pub fn expectEqualRows(want: []const []const u8, got: []const []const u8) !void {
    try testing.expectEqual(want.len, got.len);
    for (want, got) |w, g| try testing.expectEqualStrings(w, g);
}

// Small owned-table harness used by unit tests.
pub const TestTable = struct {
    app: *App = undefined,
    config: *types.Config = undefined,
    table: *Table = undefined,

    // Build a test table from an inline CSV string.
    pub fn init(self: *TestTable, alloc: std.mem.Allocator, config: types.Config, input: []const u8) !void {
        self.app = try App.testInit(alloc);
        errdefer self.app.destroy();

        const data = try csv.load(self.app, input, config.delimiter);
        var data_handed_off = false;
        errdefer if (!data_handed_off) data.deinit(self.app.alloc);

        self.config = try self.app.alloc.create(types.Config);
        errdefer self.app.alloc.destroy(self.config);
        self.config.* = config;
        errdefer self.config.deinit(self.app.alloc);
        if (config.title.len > 0) self.config.title = try self.app.alloc.dupe(u8, config.title);
        if (config.footer.len > 0) self.config.footer = try self.app.alloc.dupe(u8, config.footer);

        try self.config.bind(self.app.alloc, data.headers());
        data_handed_off = true;
        self.table = try Table.init(self.app, self.config, data);
    }

    // Release the arena and test table.
    pub fn deinit(self: *TestTable) void {
        self.table.deinit();
        self.config.deinit(self.app.alloc);
        self.app.alloc.destroy(self.config);
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
const csv = @import("csv.zig");
const std = @import("std");
const testing = std.testing;
const Table = @import("table.zig").Table;
const types = @import("types.zig");
