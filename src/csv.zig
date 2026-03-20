//
// Stores the entire csv file in memory. We strip data as it arrives.
//

pub const Csv = struct {
    rows: Rows,
    bufs: [][]u8,

    // Read a csv into memory with one owned buffer per row.
    pub fn init(
        alloc: std.mem.Allocator,
        reader: anytype,
        opts: struct { delimiter: u8 = ',', head: usize = 0 },
    ) !Csv {
        var total_timer = try std.time.Timer.start();
        var rows = std.ArrayList(Row).empty;
        var bufs = std.ArrayList([]u8).empty;
        errdefer {
            for (rows.items) |row| alloc.free(row);
            rows.deinit(alloc);
            for (bufs.items) |buf| alloc.free(buf);
            bufs.deinit(alloc);
        }

        var parser = zcsv.allocs.column.init(alloc, reader, .{ .column_delim = opts.delimiter });
        var width: ?usize = null;

        while (true) {
            const row_csv = parser.next() orelse break;
            defer row_csv.deinit();

            if (width) |expected| {
                if (row_csv.len() != expected) return error.JaggedCsv;
            } else {
                width = row_csv.len();
            }

            var total_len: usize = 0;
            for (0..row_csv.len()) |ii| {
                const field = try row_csv.field(ii);
                total_len += util.strip(u8, field.data()).len;
            }

            // make a compact owned copy of the row bytes
            const bytes = try alloc.alloc(u8, total_len);
            errdefer alloc.free(bytes);

            // our new row, with a slice for each field
            const row = try alloc.alloc(Field, row_csv.len());
            errdefer alloc.free(row);

            var cursor: usize = 0;
            for (0..row_csv.len()) |ii| {
                const field = try row_csv.field(ii);
                const trimmed = util.strip(u8, field.data());
                @memcpy(bytes[cursor..][0..trimmed.len], trimmed);
                row[ii] = bytes[cursor..][0..trimmed.len];
                cursor += trimmed.len;
            }

            // keep track of our memory
            try rows.append(alloc, row);
            errdefer _ = rows.pop();
            try bufs.append(alloc, bytes);

            if (opts.head > 0 and rows.items.len == opts.head + 1) break;
        }
        if (parser.err) |err| return err;

        // arraylist => slice
        const rows_owned = try rows.toOwnedSlice(alloc);
        errdefer {
            for (rows_owned) |row| alloc.free(row);
            alloc.free(rows_owned);
        }
        const bufs_owned = try bufs.toOwnedSlice(alloc);

        util.benchmark(" csv", total_timer.read());
        return .{
            .rows = rows_owned,
            .bufs = bufs_owned,
        };
    }

    pub fn deinit(self: Csv, alloc: std.mem.Allocator) void {
        for (self.rows) |row| alloc.free(row);
        alloc.free(self.rows);
        for (self.bufs) |buf| alloc.free(buf);
        alloc.free(self.bufs);
    }
};

//
// tests
//

test "readCsv handles quoted comma and escaped quote" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var in = std.io.fixedBufferStream("a,b\n\"x,y\",\"say \"\"hi\"\"\"\n");
    const csv = try Csv.init(alloc, in.reader(), .{});
    try std.testing.expectEqual(2, csv.rows.len);
    try std.testing.expectEqualStrings("a", csv.rows[0][0]);
    try std.testing.expectEqualStrings("b", csv.rows[0][1]);
    try std.testing.expectEqualStrings("x,y", csv.rows[1][0]);
    try std.testing.expectEqualStrings("say \"hi\"", csv.rows[1][1]);
}

test "readCsv rejects jagged rows" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var in = std.io.fixedBufferStream("a,b\nc\n");
    try std.testing.expectError(error.JaggedCsv, Csv.init(alloc, in.reader(), .{}));
}

test "readCsv rejects malformed csv" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var in = std.io.fixedBufferStream("a,b\n\"oops\n");
    try std.testing.expectError(error.UnexpectedEndOfFile, Csv.init(alloc, in.reader(), .{}));
}

test "readCsv trims whitespace" {
    const alloc = std.testing.allocator;
    var in = std.io.fixedBufferStream(" a , b \n c , d \n");
    const csv = try Csv.init(alloc, in.reader(), .{});
    defer csv.deinit(alloc);

    try std.testing.expectEqualStrings("a", csv.rows[0][0]);
    try std.testing.expectEqualStrings("b", csv.rows[0][1]);
    try std.testing.expectEqualStrings("c", csv.rows[1][0]);
    try std.testing.expectEqualStrings("d", csv.rows[1][1]);
}

test "readCsv empty input yields empty header cell" {
    const alloc = std.testing.allocator;
    var in = std.io.fixedBufferStream("");
    const csv = try Csv.init(alloc, in.reader(), .{});
    defer csv.deinit(alloc);

    try std.testing.expectEqual(1, csv.rows.len);
    try std.testing.expectEqual(1, csv.rows[0].len);
    try std.testing.expectEqual(0, csv.rows[0][0].len);
}

test "readCsv with semicolon delimiter" {
    const alloc = std.testing.allocator;
    var in = std.io.fixedBufferStream("a;b\nc;d\n");
    const csv = try Csv.init(alloc, in.reader(), .{ .delimiter = ';' });
    defer csv.deinit(alloc);

    try std.testing.expectEqual(2, csv.rows.len);
    try std.testing.expectEqualStrings("a", csv.rows[0][0]);
    try std.testing.expectEqualStrings("b", csv.rows[0][1]);
    try std.testing.expectEqualStrings("c", csv.rows[1][0]);
    try std.testing.expectEqualStrings("d", csv.rows[1][1]);
}

test "readCsv with tab delimiter" {
    const alloc = std.testing.allocator;
    var in = std.io.fixedBufferStream("a\tb\nc\td\n");
    const csv = try Csv.init(alloc, in.reader(), .{ .delimiter = '\t' });
    defer csv.deinit(alloc);

    try std.testing.expectEqual(2, csv.rows.len);
    try std.testing.expectEqualStrings("a", csv.rows[0][0]);
    try std.testing.expectEqualStrings("b", csv.rows[0][1]);
    try std.testing.expectEqualStrings("c", csv.rows[1][0]);
    try std.testing.expectEqualStrings("d", csv.rows[1][1]);
}

test "readCsv semicolon delimiter preserves commas in fields" {
    const alloc = std.testing.allocator;
    var in = std.io.fixedBufferStream("a;b\nc,1;d\n");
    const csv = try Csv.init(alloc, in.reader(), .{ .delimiter = ';' });
    defer csv.deinit(alloc);

    try std.testing.expectEqualStrings("c,1", csv.rows[1][0]);
    try std.testing.expectEqualStrings("d", csv.rows[1][1]);
}

test "deinit releases owned rows" {
    const alloc = std.testing.allocator;
    const rows = try alloc.alloc(Row, 1);
    errdefer alloc.free(rows);
    const row = try alloc.alloc(Field, 2);
    errdefer alloc.free(row);
    const buf = try alloc.dupe(u8, "ab");
    errdefer alloc.free(buf);
    row[0] = buf[0..1];
    row[1] = buf[1..2];
    rows[0] = row;
    const bufs = try alloc.alloc([]u8, 1);
    errdefer alloc.free(bufs);
    bufs[0] = buf;

    const csv: Csv = .{ .rows = rows, .bufs = bufs };
    csv.deinit(alloc);
}

const Field = @import("types.zig").Field;
const Row = @import("types.zig").Row;
const Rows = @import("types.zig").Rows;
const std = @import("std");
const util = @import("util.zig");
const zcsv = @import("zcsv");
