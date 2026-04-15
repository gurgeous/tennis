//
// Detect input formats from filename hints and sampled bytes. We support the
// following JSON types:
//
// json array  - [ { . }, { . }, ..... ] <EOF>
// jsonl       - { . }\n{ . }\n ...{ . } <EOF>
// json object - { ................... } <EOF>
//

pub const InputFormat = enum { csv, json, sqlite };

// Detect the input format from filename hints and the initial sample.
pub fn detectFormat(alloc: std.mem.Allocator, filename: ?[]const u8, sample: []const u8) !InputFormat {
    // Filename trumps everything else. Stdin doesn't have a filename, though.
    if (filename) |str| {
        if (formatFromFilename(str)) |detected| return detected;
    }

    // Examine the first few bytes, see if we might be looking at json or sqlite
    const magic = sample[0..@min(sample.len, 16)];
    const str = try util.replaceAny(u8, alloc, magic, &std.ascii.whitespace, "");
    defer alloc.free(str);
    if (std.mem.startsWith(u8, magic, "SQLite format 3")) return .sqlite;
    if (std.mem.startsWith(u8, str, "[{\"")) return .json;
    if (std.mem.startsWith(u8, str, "{\"")) return .json;

    // default to csv
    return .csv;
}

// Infer an input format from the filename extension.
pub fn formatFromFilename(path: []const u8) ?InputFormat {
    // get ext
    const ext = std.fs.path.extension(path);
    var buf: [16]u8 = undefined;
    if (ext.len > buf.len) return null;
    const lower = util.lowerAscii(&buf, ext);

    if (std.mem.eql(u8, lower, ".csv")) return .csv;
    if (std.mem.eql(u8, lower, ".json")) return .json;
    if (std.mem.eql(u8, lower, ".jsonl")) return .json;
    if (std.mem.eql(u8, lower, ".ndjson")) return .json;
    if (std.mem.eql(u8, lower, ".db")) return .sqlite;
    if (std.mem.eql(u8, lower, ".sqlite")) return .sqlite;
    if (std.mem.eql(u8, lower, ".sqlite3")) return .sqlite;
    if (std.mem.eql(u8, lower, ".tsv")) return .csv;
    return null;
}

pub fn isSqliteFile(app: *const App, alloc: std.mem.Allocator, filename: ?[]const u8, input: std.Io.File) !bool {
    // do we have an actual file?
    const path = filename orelse return false;
    if (std.mem.eql(u8, path, "-")) return false;
    if (!util.isSeekable(app.io, input)) return false;

    // sample the first few bytes to look for sqlite3 magic
    var buf: [32]u8 = undefined;
    var reader = input.reader(app.io, &.{});
    const n = try reader.interface.readSliceShort(&buf);
    try reader.seekTo(0);
    return try detectFormat(alloc, path, buf[0..n]) == .sqlite;
}

//
// testing
//

test "detectFormat" {
    const alloc = testing.allocator;
    const cases = [_]struct {
        filename: ?[]const u8,
        sample: []const u8,
        want: InputFormat,
    }{
        .{ .filename = null, .sample = "  [\n  {\"a\":1}\n", .want = .json },
        .{ .filename = null, .sample = "{\"a\":1}\n{\"a\":2}\n", .want = .json },
        .{ .filename = null, .sample = "{\"a\":1}\n", .want = .json },
        .{ .filename = null, .sample = "SQLite format 3\x00rest", .want = .sqlite },
        .{ .filename = null, .sample = "a,b\n1,2\n", .want = .csv },
        .{ .filename = "foo.json", .sample = "{\"rows\":[1,2,3]}\n", .want = .json },
        .{ .filename = "foo.JSON", .sample = "a,b\n1,2\n", .want = .json },
        .{ .filename = "foo.csv", .sample = "{\"rows\":[1,2,3]}\n", .want = .csv },
        .{ .filename = "foo.CSV", .sample = "{\"rows\":[1,2,3]}\n", .want = .csv },
        .{ .filename = "foo.db", .sample = "a,b\n1,2\n", .want = .sqlite },
        .{ .filename = "foo.SQLITE", .sample = "a,b\n1,2\n", .want = .sqlite },
        .{ .filename = "foo.sqlite3", .sample = "a,b\n1,2\n", .want = .sqlite },
        .{ .filename = "foo.tsv", .sample = "{\"a\":1}\n", .want = .csv },
        .{ .filename = "foo.TSV", .sample = "{\"a\":1}\n", .want = .csv },
        .{ .filename = "foo.ndjson", .sample = "{\"a\":1}\n", .want = .json },
        .{ .filename = "foo.NDJSON", .sample = "{\"a\":1}\n", .want = .json },
        .{ .filename = "-", .sample = "[{\"a\":1}]\n", .want = .json },
        .{ .filename = "-", .sample = "a,b\n1,2\n", .want = .csv },
    };

    for (cases) |tc| {
        try testing.expectEqual(tc.want, try detectFormat(alloc, tc.filename, tc.sample));
    }
}

const App = @import("app.zig").App;
const std = @import("std");
const testing = std.testing;
const util = @import("util.zig");
