//
// Custom/simple CSV loader. Fields are normalized when copied into DataRow.
// This is a very simple standalone csv reader.
//

// Parse buffered CSV input and return owned table data.
pub fn load(app: *App, alloc: std.mem.Allocator, bytes: []const u8, delimiter: u8) !Data {
    const timer = util.timerStart(app.io);
    var loader = CsvLoader.init(alloc, bytes, delimiter);
    defer loader.deinit();

    const data = try loader.load();
    app.benchmark("csv", util.timerRead(app.io, timer));
    return data;
}

// Parse CSV input in tests without manually constructing an App at each call site.
fn loadTest(alloc: std.mem.Allocator, bytes: []const u8, delimiter: u8) !Data {
    const app = try App.testInit(alloc);
    defer app.destroy();
    return load(app, alloc, bytes, delimiter);
}

//
// Our internal loader
//

const CsvLoader = struct {
    alloc: std.mem.Allocator,
    bytes: []const u8, // input bytes
    delimiter: u8, // delimiter passed to csv.load
    rows: std.ArrayList(DataRow) = .empty, // rows parsed so far
    ncols: ?usize = null, // for jagged checking

    // tmp state
    fields: std.ArrayList(Field) = .empty,
    buf: std.ArrayList(u8) = .empty,
    cursor: usize = 0,

    const Self = @This();

    // Initialize a loader over one buffered CSV input.
    fn init(alloc: std.mem.Allocator, bytes: []const u8, delimiter: u8) CsvLoader {
        return .{ .alloc = alloc, .bytes = bytes, .delimiter = delimiter };
    }

    // Release scratch state and any rows still owned by the loader.
    fn deinit(self: *Self) void {
        for (self.rows.items) |row| row.deinit(self.alloc);
        self.rows.deinit(self.alloc);
        self.fields.deinit(self.alloc);
        self.buf.deinit(self.alloc);
    }

    // Parse all rows and transfer ownership into Data.
    fn load(self: *Self) !Data {
        while (self.cursor < self.bytes.len) {
            try self.parseRow();
        }
        return .{ .rows = try self.rows.toOwnedSlice(self.alloc) };
    }

    // Parse one CSV row from the current cursor, append it, and advance.
    fn parseRow(self: *Self) !void {
        if (self.bytes[self.cursor] == '\n') return error.UnexpectedEndOfFile;
        if (self.bytes[self.cursor] == '\r' and self.cursor + 1 < self.bytes.len and self.bytes[self.cursor + 1] == '\n') {
            return error.UnexpectedEndOfFile;
        }

        // reset tmp state
        self.fields.clearRetainingCapacity();
        self.buf.clearRetainingCapacity();
        try self.buf.ensureTotalCapacity(self.alloc, self.bytes.len - self.cursor);

        // parse fields
        while (true) {
            const pos = self.buf.items.len;
            const done = try self.parseField();
            try self.fields.append(self.alloc, self.buf.items[pos..]);
            if (done) break;
        }

        // make sure we aren't jagged
        if (self.ncols) |exp| {
            if (self.fields.items.len != exp) return error.JaggedCsv;
        } else {
            self.ncols = self.fields.items.len;
        }

        // append row
        const row = try DataRow.init(self.alloc, self.fields.items);
        errdefer row.deinit(self.alloc);
        try self.rows.append(self.alloc, row);
    }

    // Parse one CSV field until the next delimiter, row end, or EOF.
    fn parseField(self: *Self) !bool {
        var in_quote = false;
        while (self.cursor < self.bytes.len) {
            const ch = self.bytes[self.cursor];
            self.cursor += 1;
            if (ch == '"') {
                if (in_quote and self.cursor < self.bytes.len and self.bytes[self.cursor] == '"') {
                    self.buf.appendAssumeCapacity(ch);
                    self.cursor += 1;
                } else {
                    in_quote = !in_quote;
                }
                continue;
            }

            if (!in_quote) {
                if (ch == self.delimiter) return false;
                if (ch == '\n') return true;
            }
            self.buf.appendAssumeCapacity(ch);
        }
        if (in_quote) return error.UnexpectedEndOfFile;
        return true;
    }
};

//
// testing
//

test "readCsv handles quoted comma and escaped quote" {
    const alloc = testing.allocator;
    const data = try loadTest(alloc, "a,b\n\"x,y\",\"say \"\"hi\"\"\"\n", ',');
    defer data.deinit(alloc);
    try testing.expectEqual(2, data.rows.len);
    try testing.expectEqualStrings("a", data.row(0)[0]);
    try testing.expectEqualStrings("b", data.row(0)[1]);
    try testing.expectEqualStrings("x,y", data.row(1)[0]);
    try testing.expectEqualStrings("say \"hi\"", data.row(1)[1]);
}

test "readCsv rejects jagged rows" {
    try testing.expectError(error.JaggedCsv, loadTest(testing.allocator, "a,b\nc\n", ','));
}

test "readCsv rejects malformed csv" {
    try testing.expectError(error.UnexpectedEndOfFile, loadTest(testing.allocator, "a,b\n\"oops\n", ','));
}

test "readCsv supports empty fields" {
    const alloc = testing.allocator;
    const data = try loadTest(alloc, "a,b,c\n1,,3\n", ',');
    defer data.deinit(alloc);

    try testing.expectEqualStrings("1", data.row(1)[0]);
    try testing.expectEqualStrings("", data.row(1)[1]);
    try testing.expectEqualStrings("3", data.row(1)[2]);
}

test "readCsv rejects blank lines" {
    const alloc = testing.allocator;
    try testing.expectError(error.UnexpectedEndOfFile, loadTest(alloc, "a,b\n\nc,d\n", ','));
}

test "readCsv supports leading and trailing empty fields" {
    const alloc = testing.allocator;
    const data = try loadTest(alloc, "a,b,c\n,2,3\n1,2,\n", ',');
    defer data.deinit(alloc);

    try testing.expectEqualStrings("", data.row(1)[0]);
    try testing.expectEqualStrings("2", data.row(1)[1]);
    try testing.expectEqualStrings("3", data.row(1)[2]);

    try testing.expectEqualStrings("1", data.row(2)[0]);
    try testing.expectEqualStrings("2", data.row(2)[1]);
    try testing.expectEqualStrings("", data.row(2)[2]);
}

test "readCsv supports CRLF line endings" {
    const alloc = testing.allocator;

    const data1 = try loadTest(alloc, "a,b\r\nc,d\r\n", ',');
    defer data1.deinit(alloc);
    try testing.expectEqualStrings("c", data1.row(1)[0]);
    try testing.expectEqualStrings("d", data1.row(1)[1]);
}

test "readCsv supports final row without trailing newline" {
    const alloc = testing.allocator;
    const data = try loadTest(alloc, "a,b\nc,d", ',');
    defer data.deinit(alloc);

    try testing.expectEqual(@as(usize, 2), data.rows.len);
    try testing.expectEqualStrings("c", data.row(1)[0]);
    try testing.expectEqualStrings("d", data.row(1)[1]);
}

test "readCsv supports quoted final row without trailing newline" {
    const alloc = testing.allocator;
    const data = try loadTest(alloc, "a,b\n\"x,y\",z", ',');
    defer data.deinit(alloc);

    try testing.expectEqual(@as(usize, 2), data.rows.len);
    try testing.expectEqualStrings("x,y", data.row(1)[0]);
    try testing.expectEqualStrings("z", data.row(1)[1]);
}

test "readCsv supports embedded newlines in quoted fields" {
    const alloc = testing.allocator;
    const data = try loadTest(alloc, "a,b\n\"x\ny\",z\n", ',');
    defer data.deinit(alloc);

    try testing.expectEqualStrings("x\\ny", data.row(1)[0]);
    try testing.expectEqualStrings("z", data.row(1)[1]);
}

test "readCsv supports embedded CRLF in quoted fields" {
    const alloc = testing.allocator;
    const data = try loadTest(alloc, "a,b\r\n\"x\r\ny\",z\r\n", ',');
    defer data.deinit(alloc);

    try testing.expectEqualStrings("x\\r\\ny", data.row(1)[0]);
    try testing.expectEqualStrings("z", data.row(1)[1]);
}

test "readCsv loads all rows" {
    const alloc = testing.allocator;
    const data = try loadTest(alloc, "a,b\n1,2\n3,4\n5,6\n", ',');
    defer data.deinit(alloc);

    try testing.expectEqual(@as(usize, 4), data.rows.len);
    try testing.expectEqualStrings("1", data.row(1)[0]);
    try testing.expectEqualStrings("3", data.row(2)[0]);
    try testing.expectEqualStrings("5", data.row(3)[0]);
}

test "readCsv tab delimiter allows quoted fields after spaces" {
    const alloc = testing.allocator;
    const data = try loadTest(alloc, "a\tb\n  \"x\"\t  \"y\"\n", '\t');
    defer data.deinit(alloc);

    try testing.expectEqualStrings("x", data.row(1)[0]);
    try testing.expectEqualStrings("y", data.row(1)[1]);
}

test "readCsv supports very long rows" {
    const alloc = testing.allocator;
    const long = [_]u8{'x'} ** (17 * 1024);
    const data = try loadTest(alloc, "a,b\n" ++ long ++ ",z\n", ',');
    defer data.deinit(alloc);

    try testing.expectEqual(@as(usize, 2), data.rows.len);
    try testing.expectEqualStrings(&long, data.row(1)[0]);
    try testing.expectEqualStrings("z", data.row(1)[1]);
}

const App = @import("app.zig").App;
const Data = @import("data.zig").Data;
const DataRow = @import("data.zig").DataRow;
const Field = @import("types.zig").Field;
const std = @import("std");
const testing = std.testing;
const util = @import("util.zig");
