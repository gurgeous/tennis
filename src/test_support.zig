// Small helpers for unit tests that need an owned Table.

// Assert that two string slices match element by element.
pub fn expectEqualRows(want: []const []const u8, got: []const []const u8) !void {
    try testing.expectEqual(want.len, got.len);
    for (want, got) |w, g| try testing.expectEqualStrings(w, g);
}

// Small owned-table harness used by unit tests.
pub const TestTable = struct {
    arena: std.heap.ArenaAllocator = undefined,
    table: *Table = undefined,

    // Build a test table from an inline CSV string.
    pub fn init(self: *TestTable, alloc: std.mem.Allocator, input: []const u8) !void {
        self.arena = std.heap.ArenaAllocator.init(alloc);
        errdefer self.arena.deinit();
        const data = try csv.load(self.arena.allocator(), input, ',');
        errdefer data.deinit(self.arena.allocator());
        self.table = try Table.init(self.arena.allocator(), .{}, data);
    }

    // Release the arena and test table.
    pub fn deinit(self: *TestTable) void {
        self.table.deinit();
        self.arena.deinit();
    }
};

const csv = @import("csv.zig");
const std = @import("std");
const testing = std.testing;
const Table = @import("table.zig").Table;
