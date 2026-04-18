// Typed runtime environment settings plus raw environment access.
pub const Env = struct {
    map: std.process.Environ.Map,

    BENCHMARK: bool = undefined,
    FORCE_COLOR: bool = undefined,
    NO_COLOR: bool = undefined,
    PAGER: ?[]const u8 = undefined,
    TENNIS_DEBUG: bool = undefined,
    TERM: ?[]const u8 = undefined,

    const Self = @This();

    // Build one typed environment view from the process environment.
    pub fn init(alloc: std.mem.Allocator, environ: std.process.Environ) !Env {
        var map = try std.process.Environ.createMap(environ, alloc);
        errdefer map.deinit();

        var env: Env = .{ .map = map };
        env.BENCHMARK = env.has("BENCHMARK");
        env.FORCE_COLOR = env.has("FORCE_COLOR");
        env.NO_COLOR = env.has("NO_COLOR");
        env.PAGER = env.get("PAGER");
        env.TENNIS_DEBUG = env.has("TENNIS_DEBUG");
        env.TERM = env.get("TERM");

        return env;
    }

    // Release the owned raw environment map.
    pub fn deinit(self: *Self) void {
        self.map.deinit();
    }

    // Report whether one env var exists.
    pub fn has(self: *const Self, name: []const u8) bool {
        return self.get(name) != null;
    }

    // Return one borrowed env var value when present.
    pub fn get(self: *const Self, name: []const u8) ?[]const u8 {
        return self.map.get(name);
    }

    // Return one cloned environment map for child process spawning.
    pub fn clone(self: *const Self, alloc: std.mem.Allocator) !std.process.Environ.Map {
        return try std.process.Environ.Map.clone(&self.map, alloc);
    }
};

const std = @import("std");
