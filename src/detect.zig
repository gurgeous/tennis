//
// Detect input formats from filename hints and sampled bytes. We support the
// following JSON types:
//
// json array  - [ { . }, { . }, ..... ] <EOF>
// jsonl       - { . }\n{ . }\n ...{ . } <EOF>
// json object - { ................... } <EOF>
//

pub const InputFormat = enum { csv, json, sqlite };

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

// Detect the input format from filename hints and the initial sample.
pub fn detectFormat(alloc: std.mem.Allocator, filename: ?[]const u8, sample: []const u8) !InputFormat {
    // Filename trumps everything else. Stdin doesn't have a filename, though.
    if (filename) |str| {
        if (formatFromFilename(str)) |detected| return detected;
    }

    // Examine the first few bytes, see if we might be looking at json
    const magic = sample[0..@min(sample.len, 16)];
    const str = try util.replaceAny(u8, alloc, magic, &std.ascii.whitespace, "");
    defer alloc.free(str);
    if (std.mem.startsWith(u8, magic, "SQLite format 3")) return .sqlite;
    if (std.mem.startsWith(u8, str, "[{\"")) return .json;
    if (std.mem.startsWith(u8, str, "{\"")) return .json;

    // default to csv
    return .csv;
}
//
// testing
//

test "format handles json jsonl and csv" {
    const alloc = testing.allocator;
    try testing.expectEqual(InputFormat.json, try detectFormat(alloc, null, "  [\n  {\"a\":1}\n"));
    try testing.expectEqual(InputFormat.json, try detectFormat(alloc, null, "{\"a\":1}\n{\"a\":2}\n"));
    try testing.expectEqual(InputFormat.json, try detectFormat(alloc, null, "{\"a\":1}\n"));
    try testing.expectEqual(InputFormat.sqlite, try detectFormat(alloc, null, "SQLite format 3\x00rest"));
    try testing.expectEqual(InputFormat.csv, try detectFormat(alloc, null, "a,b\n1,2\n"));
    try testing.expectEqual(InputFormat.json, try detectFormat(alloc, "foo.json", "{\"rows\":[1,2,3]}\n"));
    try testing.expectEqual(InputFormat.json, try detectFormat(alloc, "foo.JSON", "a,b\n1,2\n"));
    try testing.expectEqual(InputFormat.csv, try detectFormat(alloc, "foo.csv", "{\"rows\":[1,2,3]}\n"));
    try testing.expectEqual(InputFormat.csv, try detectFormat(alloc, "foo.CSV", "{\"rows\":[1,2,3]}\n"));
    try testing.expectEqual(InputFormat.sqlite, try detectFormat(alloc, "foo.db", "a,b\n1,2\n"));
    try testing.expectEqual(InputFormat.sqlite, try detectFormat(alloc, "foo.SQLITE", "a,b\n1,2\n"));
    try testing.expectEqual(InputFormat.sqlite, try detectFormat(alloc, "foo.sqlite3", "a,b\n1,2\n"));
    try testing.expectEqual(InputFormat.csv, try detectFormat(alloc, "foo.tsv", "{\"a\":1}\n"));
    try testing.expectEqual(InputFormat.csv, try detectFormat(alloc, "foo.TSV", "{\"a\":1}\n"));
    try testing.expectEqual(InputFormat.json, try detectFormat(alloc, "foo.ndjson", "{\"a\":1}\n"));
    try testing.expectEqual(InputFormat.json, try detectFormat(alloc, "foo.NDJSON", "{\"a\":1}\n"));
    try testing.expectEqual(InputFormat.json, try detectFormat(alloc, "-", "[{\"a\":1}]\n"));
    try testing.expectEqual(InputFormat.csv, try detectFormat(alloc, "-", "a,b\n1,2\n"));
}

const std = @import("std");
const testing = std.testing;
const util = @import("util.zig");
