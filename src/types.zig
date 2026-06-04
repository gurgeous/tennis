// Shared enums and config types used across the app.

// Shell names supported by the completion generator.
pub const CompletionShell = enum { bash, zsh };

// User-facing configuration resolved from CLI arguments.
pub const Config = struct {
    // Owned argv backing CLI string fields that point into parsed arguments.
    argv: []const []const u8 = &.{},
    completion: ?CompletionShell = null,
    help: bool = false,
    version: bool = false,

    border: border.BorderName = .rounded,
    big1: []const u8 = "",
    big2: []const u8 = "",
    big3: []const u8 = "",
    color: Color = .on,
    deselect: []const u8 = "",
    delimiter: u8 = ',',
    digits: usize = 3,
    filter: []const u8 = "",
    filename: ?[]const u8 = null,
    head: usize = 0,
    pager: bool = false,
    peek: bool = false,
    reverse: bool = false,
    row_numbers: bool = false,
    select: []const u8 = "",
    shuffle: bool = false,
    sort: []const u8 = "",
    table: []const u8 = "",
    tail: usize = 0,
    theme: Theme = .auto,
    title: []const u8 = "", // always owned (not in argv)
    footer: []const u8 = "", // always owned (not in argv)
    vanilla: bool = false,
    width: Width = .auto,
    zebra: bool = false,
    // Bound header indexes populated after data load for select/deselect/sort.
    deselect_cols: []usize = &.{},
    select_cols: []usize = &.{},
    sort_cols: []usize = &.{},
    // Test-only shuffle seed for deterministic row order assertions.
    srand: u64 = 0,

    // Resolve any header-based config against the loaded header row.
    pub fn bind(self: *Config, alloc: std.mem.Allocator, headers: Row) !void {
        self.select_cols = resolveColumns(alloc, headers, self.select) catch return error.InvalidSelect;
        self.deselect_cols = resolveColumns(alloc, headers, self.deselect) catch return error.InvalidDeselect;
        self.sort_cols = resolveColumns(alloc, headers, self.sort) catch return error.InvalidSort;
    }

    // Release strings and resolved column slices owned by this config.
    pub fn deinit(self: Config, alloc: std.mem.Allocator) void {
        if (self.title.len > 0) alloc.free(self.title);
        if (self.footer.len > 0) alloc.free(self.footer);
        util.deepFree(u8, alloc, self.argv);
        alloc.free(self.deselect_cols);
        alloc.free(self.select_cols);
        alloc.free(self.sort_cols);
    }
};

// Width selection mode for the table layout engine.
pub const Width = union(enum) {
    auto,
    chars: usize,
    min,
    max,
};

// Resolve a comma-separated column spec into header indexes.
pub fn resolveColumns(alloc: std.mem.Allocator, headers: Row, spec: []const u8) ![]usize {
    if (spec.len == 0) return alloc.alloc(usize, 0);

    var cols: std.ArrayList(usize) = .empty;
    defer cols.deinit(alloc);

    var it = std.mem.splitScalar(u8, spec, ',');
    while (it.next()) |raw| {
        const name = util.strip(u8, raw);
        if (name.len == 0) return error.InvalidColumns;
        for (headers, 0..) |header, ii| {
            if (std.ascii.eqlIgnoreCase(header, name)) {
                try cols.append(alloc, ii);
                break;
            }
        } else return error.InvalidColumns;
    }

    return cols.toOwnedSlice(alloc);
}

// Row/Field plus a simple two-field entry pair.
pub const Field = []const u8;
pub const Row = []const Field;
pub const Entry = [2]Field;

// simple enums for Config
pub const Color = enum { auto, off, on };
pub const Theme = enum { auto, dark, light };

//
// testing
//

test "Config.bind resolves case insensitive header names" {
    var config: Config = .{
        .sort = " NAME , score ",
        .select = "score,name,score",
        .deselect = " SCORE ",
    };
    defer config.deinit(testing.allocator);
    try config.bind(testing.allocator, &.{ "name", "score" });

    try testing.expectEqualSlices(usize, &.{ 0, 1 }, config.sort_cols);
    try testing.expectEqualSlices(usize, &.{ 1, 0, 1 }, config.select_cols);
    try testing.expectEqualSlices(usize, &.{1}, config.deselect_cols);
}

test "Config.bind rejects bad column specs" {
    var bad_sort: Config = .{ .sort = "name," };
    defer bad_sort.deinit(testing.allocator);
    try testing.expectError(error.InvalidSort, bad_sort.bind(testing.allocator, &.{ "name", "score" }));

    var bad_select: Config = .{ .select = "bogus" };
    defer bad_select.deinit(testing.allocator);
    try testing.expectError(error.InvalidSelect, bad_select.bind(testing.allocator, &.{ "name", "score" }));

    var bad_deselect: Config = .{ .deselect = "bogus" };
    defer bad_deselect.deinit(testing.allocator);
    try testing.expectError(error.InvalidDeselect, bad_deselect.bind(testing.allocator, &.{ "name", "score" }));
}

test "resolveColumns accepts empty spec" {
    const cols = try resolveColumns(testing.allocator, &.{ "name", "score" }, "");
    defer testing.allocator.free(cols);
    try testing.expectEqual(@as(usize, 0), cols.len);
}

const border = @import("border.zig");
const std = @import("std");
const testing = std.testing;
const util = @import("util.zig");
