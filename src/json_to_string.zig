// Turn one scanned JSON value into a string slice for table display.
pub fn jsonToString(alloc: std.mem.Allocator, scan: *json.Scanner) ![]const u8 {
    const next = try nextRawToken(alloc, scan);
    return switch (next.token) {
        // scalars
        .null => "",
        .true, .false, .number, .allocated_number => next.raw,
        .string, .allocated_string => util.tokenBytes(next.token),
        // deep
        .array_begin, .object_begin => {
            // re-render nested obj to clean up whitespace
            var out = std.Io.Writer.Allocating.init(alloc);
            errdefer out.deinit();
            try writeValue(&out.writer, alloc, scan, next);
            return out.toOwnedSlice();
        },
        else => error.SyntaxError,
    };
}

// Write one JSON value using compact structure punctuation and raw scalar tokens.
fn writeValue(writer: *std.Io.Writer, alloc: std.mem.Allocator, scan: *json.Scanner, next: RawToken) anyerror!void {
    switch (next.token) {
        // scalars
        .null, .true, .false, .number, .allocated_number, .string, .allocated_string => {
            try writer.writeAll(next.raw);
        },
        // deep
        .array_begin => try writeArray(writer, alloc, scan),
        .object_begin => try writeObject(writer, alloc, scan),
        else => return error.SyntaxError,
    }
}

fn writeArray(writer: *std.Io.Writer, alloc: std.mem.Allocator, scan: *json.Scanner) anyerror!void {
    var first = true;
    try writer.writeByte('[');
    var el = try nextRawToken(alloc, scan);
    while (el.token != .array_end) : (el = try nextRawToken(alloc, scan)) {
        if (first) first = false else try writer.writeAll(", ");
        try writeValue(writer, alloc, scan, el);
    }
    try writer.writeByte(']');
}

fn writeObject(writer: *std.Io.Writer, alloc: std.mem.Allocator, scan: *json.Scanner) anyerror!void {
    var first = true;
    try writer.writeByte('{');
    var key = try nextRawToken(alloc, scan);
    while (key.token != .object_end) : (key = try nextRawToken(alloc, scan)) {
        if (first) first = false else try writer.writeAll(", ");
        try writer.writeAll(key.raw);
        try writer.writeByte(':');
        try writeValue(writer, alloc, scan, try nextRawToken(alloc, scan));
    }
    try writer.writeByte('}');
}

const RawToken = struct { token: json.Token, raw: []const u8 };

// Return the next token together with its raw byte span in the input.
fn nextRawToken(alloc: std.mem.Allocator, scan: *json.Scanner) !RawToken {
    _ = try scan.peekNextTokenType();
    const start = scan.cursor;
    const token = try scan.nextAlloc(alloc, .alloc_if_needed);
    return .{ .token = token, .raw = scan.input[start..scan.cursor] };
}

//
// testing
//

test "jsonToString decodes escaped strings" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var scan = json.Scanner.initCompleteInput(arena.allocator(), "\"a\\tb\"");
    defer scan.deinit();

    const got = try jsonToString(arena.allocator(), &scan);
    try testing.expectEqualStrings("a\tb", got);
}

test "jsonToString preserves deep raw json" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var scan = json.Scanner.initCompleteInput(arena.allocator(), "{\"ok\":true}");
    defer scan.deinit();

    const got = try jsonToString(arena.allocator(), &scan);
    try testing.expectEqualStrings("{\"ok\":true}", got);
}

test "jsonToString compacts pretty nested json" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var scan = json.Scanner.initCompleteInput(arena.allocator(),
        \\{
        \\  "6": 0,
        \\  "12": 168,
        \\  "24": 820,
        \\  "36": 1073
        \\}
    );
    defer scan.deinit();

    const got = try jsonToString(arena.allocator(), &scan);
    try testing.expectEqualStrings("{\"6\":0, \"12\":168, \"24\":820, \"36\":1073}", got);
}

test "jsonToString preserves nested scalar token escapes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var scan = json.Scanner.initCompleteInput(arena.allocator(),
        \\["a\\tb",true,null,123]
    );
    defer scan.deinit();

    const got = try jsonToString(arena.allocator(), &scan);
    try testing.expectEqualStrings("[\"a\\\\tb\", true, null, 123]", got);
}

const json = std.json;
const std = @import("std");
const testing = std.testing;
const util = @import("util.zig");
