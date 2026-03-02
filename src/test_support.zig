const std = @import("std");
const Table = @import("table.zig").Table;

pub const TestTable = struct {
    arena: std.heap.ArenaAllocator = undefined,
    table: Table = undefined,

    pub fn init(self: *TestTable, alloc: std.mem.Allocator) void {
        self.arena = std.heap.ArenaAllocator.init(alloc);
        self.table = .init(self.arena.allocator(), .{});
    }

    pub fn deinit(self: *TestTable) void {
        self.arena.deinit();
    }
};
