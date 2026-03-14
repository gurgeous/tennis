const std = @import("std");
const Table = @import("table.zig").Table;

pub const TestTable = struct {
    arena: std.heap.ArenaAllocator = undefined,
    table: Table = undefined,

    pub fn init(self: *TestTable, alloc: std.mem.Allocator, input: []const u8) !void {
        self.arena = std.heap.ArenaAllocator.init(alloc);
        errdefer self.arena.deinit();
        var in = std.io.fixedBufferStream(input);
        self.table = try .init(self.arena.allocator(), .{}, in.reader());
    }

    pub fn deinit(self: *TestTable) void {
        self.table.deinit();
        self.arena.deinit();
    }
};
