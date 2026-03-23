//
// Parse JSON data. We support the following JSON types:
//
// json array  - [ { . }, { . }, ..... ] <EOF>
// jsonl       - { . }\n{ . }\n ...{ . } <EOF>
// json object - { ................... } <EOF>
//

//
// Main entry point
//

pub fn load(alloc: std.mem.Allocator, bytes: []const u8) !Data {
    var timer = try std.time.Timer.start();
    defer util.benchmark("json", timer.read());

    // empty input?
    if (bytes.len == 0) return .{ .rows = try alloc.alloc(DataRow, 0) };

    // pretty braindead, just try JSON and fallback to JSONL
    const data = loadJson(alloc, bytes) catch |err|
        if (err == error.SyntaxError)
            try loadJsonl(alloc, bytes)
        else
            return err;

    return data;
}

// Load one JSON document that is either an array of objects or one top-level object.
fn loadJson(alloc: std.mem.Allocator, bytes: []const u8) !Data {
    const loader = try JsonLoader.create(alloc, bytes);
    defer loader.destroy();
    return loader.load();
}

// Load JSONL by wrapping the lines into one synthetic JSON array.
fn loadJsonl(alloc: std.mem.Allocator, bytes: []const u8) !Data {
    const body = try jsonlToArray(alloc, bytes);
    defer alloc.free(body);
    return loadJson(alloc, body);
}

// Wrap JSONL into a JSON array
fn jsonlToArray(alloc: std.mem.Allocator, bytes: []const u8) ![]u8 {
    const jsonl = util.strip(u8, bytes);
    const json = try alloc.alloc(u8, jsonl.len + 2);
    errdefer alloc.free(json);
    var ii: usize = 0;
    json[ii] = '[';
    ii += 1;
    for (jsonl) |ch| {
        json[ii] = if (ch == '\n') ',' else ch;
        ii += 1;
    }
    json[ii] = ']';
    return json;
}

//
// The loader
//

const JsonLoader = struct {
    parent: std.mem.Allocator,
    bytes: []const u8, // input bytes
    arena: std.heap.ArenaAllocator,
    alloc: std.mem.Allocator = undefined,
    mode: enum { array, object } = .array,
    json: std.ArrayList([]Entry) = .empty, // parsed json objects
    keys: std.StringArrayHashMap(void) = undefined, // list of all keys discovered in json

    //
    // ctor/dtor
    //

    const Self = @This();

    // Allocate one loader with a stable address so it can cache the arena allocator.
    fn create(parent: std.mem.Allocator, bytes: []const u8) !*JsonLoader {
        const arena = std.heap.ArenaAllocator.init(parent);
        const self = try parent.create(JsonLoader);
        self.* = .{ .parent = parent, .bytes = bytes, .arena = arena };
        self.alloc = self.arena.allocator();
        self.keys = std.StringArrayHashMap(void).init(self.alloc);
        return self;
    }

    fn destroy(self: *Self) void {
        const parent = self.parent;
        self.arena.deinit();
        parent.destroy(self);
    }

    //
    // Main entry point
    //

    fn load(self: *Self) !Data {
        var rows: std.ArrayList(DataRow) = .empty;
        errdefer {
            for (rows.items) |row| row.deinit(self.parent);
            rows.deinit(self.parent);
        }

        // parse json
        var timer = try std.time.Timer.start();
        try self.parseJson();
        util.benchmark(" json.parse", timer.read());
        defer util.benchmark(" json.rows", timer.read());

        timer = try std.time.Timer.start();
        switch (self.mode) {
            .array => {
                const headers = try DataRow.init(self.parent, self.keys.keys());
                try rows.append(self.parent, headers);
                try self.buildRows(&rows);
            },
            .object => {
                const headers = try DataRow.init(self.parent, &.{ "key", "value" });
                try rows.append(self.parent, headers);
                try self.buildObjectRows(&rows, self.json.items[0]);
            },
        }

        return .{ .rows = try rows.toOwnedSlice(self.parent) };
    }

    // Parse the top-level json value into temporary objects.
    fn parseJson(self: *Self) !void {
        var scan = std.json.Scanner.initCompleteInput(self.alloc, self.bytes);
        defer scan.deinit();

        switch (try scan.next()) {
            .array_begin => {
                self.mode = .array;
                while (true) {
                    switch (try scan.nextAlloc(self.alloc, .alloc_if_needed)) {
                        .array_end => break,
                        .object_begin => {
                            try self.json.append(self.alloc, try self.parseObject(&scan));
                        },
                        else => return error.SyntaxError,
                    }
                }
            },
            .object_begin => {
                self.mode = .object;
                try self.json.append(self.alloc, try self.parseObject(&scan));
            },
            else => return error.SyntaxError,
        }

        // must be done
        if (try scan.next() != .end_of_document) return error.SyntaxError;
    }

    // Parse a single, potentially deep object into a flat array of entries
    fn parseObject(self: *Self, scan: *std.json.Scanner) ![]Entry {
        var list = std.ArrayList(Entry).empty;
        while (true) {
            const token = try scan.nextAlloc(self.alloc, .alloc_if_needed);
            switch (token) {
                .allocated_string, .string => {
                    const key = util.tokenBytes(token);
                    const value = try jsonToString(self.alloc, scan);
                    try list.append(self.alloc, .{ key, value });

                    // also add this key to our grand list of keys
                    _ = try self.keys.getOrPut(key);
                },
                .object_end => break,
                else => unreachable,
            }
        }
        return try list.toOwnedSlice(self.alloc);
    }

    // convert all json objects => DataRows
    fn buildRows(self: *Self, rows: *std.ArrayList(DataRow)) !void {
        const ncols = self.keys.keys().len;
        const tmp = try self.alloc.alloc(Field, ncols);

        for (self.json.items) |object| {
            @memset(tmp, "");
            for (object) |entry| {
                const ii = self.keys.getIndex(entry[0]) orelse unreachable;
                if (tmp[ii].len > 0) continue;
                tmp[ii] = entry[1];
            }
            const data_row = try DataRow.init(self.parent, tmp);
            try rows.append(self.parent, data_row);
        }
    }

    // Convert one top-level object into key/value rows.
    fn buildObjectRows(self: *Self, rows: *std.ArrayList(DataRow), object: []Entry) !void {
        for (object) |entry| {
            const data_row = try DataRow.init(self.parent, &.{ entry[0], entry[1] });
            try rows.append(self.parent, data_row);
        }
    }
};

//
// testing
//

test "reads json row shapes" {
    const cases = [_]struct {
        input: []const u8,
        nrows: usize,
        checks: []const struct { row: usize, fields: []const []const u8 },
    }{
        .{
            .input =
            \\[
            \\  {"name":"alice","score":1234,"tags":["a","b"]},
            \\  {"name":"bob","city":"denver","meta":{"ok":true}}
            \\]
            ,
            .nrows = 3,
            .checks = &.{
                .{ .row = 0, .fields = &.{ "name", "score", "tags", "city", "meta" } },
                .{ .row = 1, .fields = &.{ "alice", "1234", "[\"a\",\"b\"]", "", "" } },
                .{ .row = 2, .fields = &.{ "bob", "", "", "denver", "{\"ok\":true}" } },
            },
        },
        .{
            .input =
            \\{"name":"alice","score":1234,"tags":["a","b"]}
            \\{"name":"bob","city":"denver","meta":{"ok":true}}
            \\{"name":"cara","score":99}
            ,
            .nrows = 4,
            .checks = &.{
                .{ .row = 1, .fields = &.{ "alice", "1234", "[\"a\",\"b\"]", "", "" } },
                .{ .row = 2, .fields = &.{ "bob", "", "", "denver", "{\"ok\":true}" } },
            },
        },
    };

    for (cases) |tc| {
        const rows = try initTest(testing.allocator, tc.input);
        defer rows.deinit(testing.allocator);
        try testing.expectEqual(tc.nrows, rows.rows.len);
        for (tc.checks) |check| try expectRow(rows, check.row, check.fields);
    }
}

test "reads single object json as key value rows" {
    const rows = try initTest(testing.allocator,
        \\{"name":"alice","score":1234,"tags":["a","b"],"meta":{"ok":true}}
    );
    defer rows.deinit(testing.allocator);

    try testing.expectEqual(@as(usize, 5), rows.rows.len);
    try expectRow(rows, 0, &.{ "key", "value" });
    try expectRow(rows, 1, &.{ "name", "alice" });
    try expectRow(rows, 2, &.{ "score", "1234" });
    try expectRow(rows, 3, &.{ "tags", "[\"a\",\"b\"]" });
    try expectRow(rows, 4, &.{ "meta", "{\"ok\":true}" });
}

test "reads jsonl through ambiguous json format" {
    const rows = try initTest(testing.allocator,
        \\{"name":"alice","score":1234}
        \\{"name":"bob","score":5678}
    );
    defer rows.deinit(testing.allocator);

    try testing.expectEqual(@as(usize, 3), rows.rows.len);
    try expectRow(rows, 0, &.{ "name", "score" });
    try expectRow(rows, 1, &.{ "alice", "1234" });
    try expectRow(rows, 2, &.{ "bob", "5678" });
}

test "reads jsonl with CRLF line endings" {
    const rows = try initTest(
        testing.allocator,
        "{\"name\":\"alice\",\"score\":1234}\r\n{\"name\":\"bob\",\"score\":5678}\r\n",
    );
    defer rows.deinit(testing.allocator);

    try testing.expectEqual(@as(usize, 3), rows.rows.len);
    try expectRow(rows, 0, &.{ "name", "score" });
    try expectRow(rows, 1, &.{ "alice", "1234" });
    try expectRow(rows, 2, &.{ "bob", "5678" });
}

test "rejects blank lines in jsonl" {
    try testing.expectError(error.SyntaxError, initTest(
        testing.allocator,
        "{\"name\":\"alice\"}\n\n{\"name\":\"bob\"}\n",
    ));
}

test "renders empty strings and bounded floats" {
    const rows = try initTest(testing.allocator,
        \\[
        \\  {"name":"","score":1.23456789}
        \\]
    );
    defer rows.deinit(testing.allocator);

    try testing.expectEqualStrings("", rows.row(1)[0]);
    try testing.expectEqualStrings("1.23456789", rows.row(1)[1]);
}

test "renders escaped strings via decoded value" {
    const rows = try initTest(testing.allocator,
        \\[
        \\  {"name":"a\tb","quote":"he said \"hi\""}
        \\]
    );
    defer rows.deinit(testing.allocator);

    try testing.expectEqualStrings("a\\tb", rows.row(1)[0]);
    try testing.expectEqualStrings("he said \"hi\"", rows.row(1)[1]);
}

test "rejects non object json rows" {
    try testing.expectError(error.SyntaxError, initTest(testing.allocator, "[1,2,3]"));
    try testing.expectError(error.SyntaxError, initTest(testing.allocator, "1\n"));
}

test "reads empty json array and empty jsonl" {
    const cases = [_]struct { input: []const u8, nrows: usize }{
        .{ .input = "[]", .nrows = 1 },
        .{ .input = "", .nrows = 0 },
    };

    for (cases) |tc| {
        const rows = try initTest(testing.allocator, tc.input);
        defer rows.deinit(testing.allocator);
        try testing.expectEqual(tc.nrows, rows.rows.len);
        if (tc.nrows > 0) try testing.expectEqual(@as(usize, 0), rows.row(0).len);
    }
}

test "renders null booleans and schema union" {
    const rows = try initTest(testing.allocator,
        \\[
        \\  {"name":"alice","ok":true,"score":null},
        \\  {"name":"bob","ok":false,"city":"denver"}
        \\]
    );
    defer rows.deinit(testing.allocator);

    try expectRow(rows, 0, &.{ "name", "ok", "score", "city" });
    try expectRow(rows, 1, &.{ "alice", "true", "", "" });
    try expectRow(rows, 2, &.{ "bob", "false", "", "denver" });
}

test "reads empty object in json array" {
    const rows = try initTest(testing.allocator,
        \\[
        \\  {},
        \\  {"name":"bob"}
        \\]
    );
    defer rows.deinit(testing.allocator);

    try testing.expectEqual(@as(usize, 3), rows.rows.len);
    try expectRow(rows, 0, &.{"name"});
    try expectRow(rows, 1, &.{""});
    try expectRow(rows, 2, &.{"bob"});
}

test "duplicate keys use first value" {
    const rows = try initTest(testing.allocator,
        \\[
        \\  {"a":1,"a":2}
        \\]
    );
    defer rows.deinit(testing.allocator);

    try testing.expectEqual(@as(usize, 2), rows.rows.len);
    try expectRow(rows, 0, &.{"a"});
    try expectRow(rows, 1, &.{"1"});
}

fn initTest(alloc: std.mem.Allocator, bytes: []const u8) !Data {
    return load(alloc, bytes);
}

fn expectRow(rows: Data, index: usize, want: []const []const u8) !void {
    try testing.expectEqual(want.len, rows.row(index).len);
    for (want, rows.row(index)) |w, got| try testing.expectEqualStrings(w, got);
}

const Data = @import("data.zig").Data;
const DataRow = @import("data.zig").DataRow;
const Entry = @import("types.zig").Entry;
const Field = @import("types.zig").Field;
const jsonToString = @import("json_to_string.zig").jsonToString;
const std = @import("std");
const testing = std.testing;
const util = @import("util.zig");
