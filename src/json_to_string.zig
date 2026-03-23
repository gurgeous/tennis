// Turn one scanned JSON value into a string slice for table display.

pub fn jsonToString(alloc: std.mem.Allocator, scan: *std.json.Scanner) ![]const u8 {
    _ = try scan.peekNextTokenType();
    const start = scan.cursor;

    const token = try scan.nextAlloc(alloc, .alloc_if_needed);
    return switch (token) {
        .null => "",
        .true, .false, .number, .allocated_number => scan.input[start..scan.cursor],
        .string, .allocated_string => util.tokenBytes(token),
        .array_begin, .object_begin => {
            try deep(alloc, scan, token);
            return scan.input[start..scan.cursor];
        },
        else => error.SyntaxError,
    };
}

// Consume a deep array or object so the scanner cursor lands at its end.
fn deep(alloc: std.mem.Allocator, scan: *std.json.Scanner, token: std.json.Token) !void {
    switch (token) {
        .array_begin => while (true) {
            const t = try scan.nextAlloc(alloc, .alloc_if_needed);
            switch (t) {
                .array_begin, .object_begin => try deep(alloc, scan, t),
                .array_end => return,
                else => {},
            }
        },
        .object_begin => while (true) {
            switch (try scan.nextAlloc(alloc, .alloc_if_needed)) {
                .string, .allocated_string => {
                    const t = try scan.nextAlloc(alloc, .alloc_if_needed);
                    switch (t) {
                        .array_begin, .object_begin => try deep(alloc, scan, t),
                        else => {},
                    }
                },
                .object_end => return,
                else => {},
            }
        },
        else => unreachable,
    }
}

//
// testing
//

test "jsonToString decodes escaped strings" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var scan = std.json.Scanner.initCompleteInput(arena.allocator(), "\"a\\tb\"");
    defer scan.deinit();

    const got = try jsonToString(arena.allocator(), &scan);
    try testing.expectEqualStrings("a\tb", got);
}

test "jsonToString preserves deep raw json" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var scan = std.json.Scanner.initCompleteInput(arena.allocator(), "{\"ok\":true}");
    defer scan.deinit();

    const got = try jsonToString(arena.allocator(), &scan);
    try testing.expectEqualStrings("{\"ok\":true}", got);
}

const std = @import("std");
const testing = std.testing;
const util = @import("util.zig");
