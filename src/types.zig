// Shared enums and config types used across the app.

// Shell names supported by the completion generator.
pub const CompletionShell = enum { bash, zsh };

// User-facing configuration resolved from CLI arguments.
pub const Config = struct {
    border: border.BorderName = .rounded,
    color: Color = .on,
    delimiter: u8 = ',',
    digits: usize = 3,
    filter: []const u8 = "",
    filename: ?[]const u8 = null,
    head: usize = 0,
    peek: bool = false,
    reverse: bool = false,
    row_numbers: bool = false,
    select: []const u8 = "",
    shuffle: bool = false,
    sort: []const u8 = "",
    tail: usize = 0,
    theme: Theme = .auto,
    title: []const u8 = "",
    footer: []const u8 = "",
    vanilla: bool = false,
    width: usize = 0,
    zebra: bool = false,
    // Bound header indexes populated after data load for select/sort.
    select_cols: []usize = &.{},
    sort_cols: []usize = &.{},
    // Test-only shuffle seed for deterministic row order assertions.
    srand: u64 = 0,

    // Resolve any header-based config against the loaded header row.
    pub fn bind(self: *Config, alloc: std.mem.Allocator, headers: Row) !void {
        if (self.select.len > 0) {
            self.select_cols = resolveColumns(alloc, headers, self.select) catch return error.InvalidSelect;
        }
        if (self.sort.len > 0) {
            self.sort_cols = resolveColumns(alloc, headers, self.sort) catch return error.InvalidSort;
        }
    }

    // Release any resolved config slices owned by a bound config.
    pub fn deinit(self: Config, alloc: std.mem.Allocator) void {
        if (self.title.len > 0) alloc.free(self.title);
        if (self.footer.len > 0) alloc.free(self.footer);
        alloc.free(self.select_cols);
        alloc.free(self.sort_cols);
    }
};

// Resolve a comma-separated column spec into header indexes.
fn resolveColumns(alloc: std.mem.Allocator, headers: Row, spec: []const u8) ![]usize {
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

// Top-level CLI event returned from arg parsing.
pub const MainEvent = union(enum) {
    run: Config,
    banner,
    help,
    version,
    completion: CompletionShell,
    fatal: failure.Failure,

    // Release any owned failure data attached to this event.
    pub fn deinit(self: MainEvent, alloc: std.mem.Allocator) void {
        switch (self) {
            .fatal => |fatal| fatal.deinit(alloc),
            .run => |*config| config.deinit(alloc),
            else => {},
        }
    }

    // Move the owned failure out of this event and disarm later cleanup.
    pub fn takeFailure(self: *MainEvent) failure.Failure {
        const fatal = self.fatal;
        self.* = .banner;
        return fatal;
    }
};

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
    var config: Config = .{ .sort = " NAME , score ", .select = "score,name,score" };
    defer config.deinit(testing.allocator);
    try config.bind(testing.allocator, &.{ "name", "score" });

    try testing.expectEqualSlices(usize, &.{ 0, 1 }, config.sort_cols);
    try testing.expectEqualSlices(usize, &.{ 1, 0, 1 }, config.select_cols);
}

test "Config.bind rejects bad column specs" {
    var bad_sort: Config = .{ .sort = "name," };
    defer bad_sort.deinit(testing.allocator);
    try testing.expectError(error.InvalidSort, bad_sort.bind(testing.allocator, &.{ "name", "score" }));

    var bad_select: Config = .{ .select = "bogus" };
    defer bad_select.deinit(testing.allocator);
    try testing.expectError(error.InvalidSelect, bad_select.bind(testing.allocator, &.{ "name", "score" }));
}

const border = @import("border.zig");
const failure = @import("failure.zig");
const std = @import("std");
const testing = std.testing;
const util = @import("util.zig");
