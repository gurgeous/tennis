//
// chrome constants
//

const box = [_][]const u8{
    "╭─┬─╮", // 0
    "│ │ │", // 1
    "├─┼─┤", // 2
    "╰─┴─╯", // 3
};

// grab each part of the box to get our cardinal chrome characters
const nw = boxch(0, 0);
const n = boxch(0, 2);
const ne = boxch(0, 4);
const w = boxch(2, 0);
const c = boxch(2, 2);
const e = boxch(2, 4);
const sw = boxch(3, 0);
const s = boxch(3, 2);
const se = boxch(3, 4);

// horizontal/vertical chrome
const bar = boxch(0, 1);
const pipe = boxch(1, 0);

const Align = enum { left, center };

//
// Render
//

pub const Render = struct {
    table: *Table,
    writer: *std.Io.Writer,
    records: [][][]const u8,
    layout: Layout,

    pub fn init(table: *Table, writer: *std.Io.Writer, layout: Layout, records: [][][]const u8) Render {
        return .{
            .table = table,
            .writer = writer,
            .records = records,
            .layout = layout,
        };
    }

    pub fn render(self: *Render) !void {
        // A csv with zero data rows is intentionally rendered as an "empty
        // table", even if the parser produced a single header row.
        if (self.layout.widths.len == 0) {
            return self.renderEmpty();
        }

        if (self.table.config.title.len > 0) {
            try self.renderSep(nw, bar, ne, bar);
            try self.renderTitle();
            try self.renderSep(w, bar, e, n);
        } else {
            try self.renderSep(nw, bar, ne, n);
        }
        try self.renderRow(0); // headers
        try self.renderSep(w, bar, e, c);
        for (1..self.records.len) |ii| {
            try self.renderRow(ii);
        }
        try self.renderSep(sw, bar, se, s);
    }

    // render a separator line with these border chars
    fn renderSep(self: *Render, left: []const u8, line: []const u8, right: []const u8, middle: []const u8) !void {
        if (self.table.style.chrome.len > 0) {
            try self.writer.writeAll(self.table.style.chrome);
        }

        for (self.layout.widths, 0..) |width, i| {
            if (i == 0) {
                try self.writer.writeAll(left);
            } else {
                try self.writer.writeAll(middle);
            }
            for (0..width + 2) |_| try self.writer.writeAll(line);
        }
        try self.writer.writeAll(right);
        if (self.table.style.chrome.len > 0) {
            try self.writer.writeAll(ansi.reset);
        }
        try self.writer.writeByte('\n');
    }

    // render title line
    fn renderTitle(self: *Render) !void {
        const width = self.layout.tableWidth() - 4;

        try appendStyled(self.writer, self.table.style.chrome, pipe);
        try self.writer.writeByte(' ');
        try writeStyledExactly(self.writer, self.table.style.title, self.table.config.title, width, .center);
        try self.writer.writeByte(' ');
        try appendStyled(self.writer, self.table.style.chrome, pipe);
        try self.writer.writeByte('\n');
    }

    // render data row
    fn renderRow(self: *Render, ii: usize) !void {
        const row = self.records[ii];
        try appendStyled(self.writer, self.table.style.chrome, pipe);

        var col: usize = 0;
        if (self.table.config.row_numbers) {
            var num_buf: [32]u8 = undefined;
            const label = if (ii == 0) "#" else try std.fmt.bufPrint(&num_buf, "{d}", .{ii});

            try self.writer.writeByte(' ');
            if (ii == 0) {
                try writeStyledExactly(self.writer, self.table.style.headers[0], label, self.layout.widths[col], .left);
            } else {
                try writeStyledExactly(self.writer, self.table.style.chrome, label, self.layout.widths[col], .left);
            }
            try self.writer.writeByte(' ');
            try appendStyled(self.writer, self.table.style.chrome, pipe);
            col += 1;
        }

        for (row) |field| {
            const is_placeholder = field.len == 0;
            const val = if (is_placeholder) "—" else field;

            const cell_style = if (ii == 0)
                self.table.style.headers[col % self.table.style.headers.len]
            else if (is_placeholder)
                self.table.style.chrome
            else
                self.table.style.field;

            try self.writer.writeByte(' ');
            try writeStyledExactly(self.writer, cell_style, val, self.layout.widths[col], .left);
            try self.writer.writeByte(' ');
            try appendStyled(self.writer, self.table.style.chrome, pipe);
            col += 1;
        }

        try self.writer.writeByte('\n');
    }

    fn renderEmpty(self: *Render) !void {
        const title = "empty table";
        const body = "no data";
        const width = @max(util.displayWidth(title), util.displayWidth(body));

        try self.renderEmptySep(nw, bar, ne, width);
        try self.renderEmptyRow(self.table.style.title, title, width);
        try self.renderEmptySep(w, bar, e, width);
        try self.renderEmptyRow(self.table.style.field, body, width);
        try self.renderEmptySep(sw, bar, se, width);
    }

    fn renderEmptySep(self: *Render, left: []const u8, line: []const u8, right: []const u8, width: usize) !void {
        try appendStyled(self.writer, self.table.style.chrome, left);
        for (0..width + 2) |_| try appendStyled(self.writer, self.table.style.chrome, line);
        try appendStyled(self.writer, self.table.style.chrome, right);
        try self.writer.writeByte('\n');
    }

    fn renderEmptyRow(self: *Render, text_style: []const u8, text: []const u8, width: usize) !void {
        try appendStyled(self.writer, self.table.style.chrome, pipe);
        try self.writer.writeByte(' ');
        try writeStyledExactly(self.writer, text_style, text, width, .center);
        try self.writer.writeByte(' ');
        try appendStyled(self.writer, self.table.style.chrome, pipe);
        try self.writer.writeByte('\n');
    }
};

//
// helpers
//

fn boxch(comptime row: usize, comptime col: usize) []const u8 {
    comptime {
        const line = box[row];
        var i: usize = 0;
        var start: usize = 0;
        while (start < line.len) : (i += 1) {
            const len = std.unicode.utf8ByteSequenceLength(line[start]) catch @compileError("invalid BOX utf8");
            if (i == col) return line[start .. start + len];
            start += len;
        }
        @compileError("invalid BOX index");
    }
}

fn writeExactly(writer: *std.Io.Writer, text: []const u8, width: usize, al: Align) !void {
    const display_width = util.displayWidth(text);
    if (display_width == width) {
        try writer.writeAll(text);
        return;
    }

    if (display_width < width) {
        const pad = width - display_width;
        if (al == .center) {
            const left = pad / 2;
            const right = pad - left;
            try writeSpaces(writer, left);
            try writer.writeAll(text);
            try writeSpaces(writer, right);
        } else {
            try writer.writeAll(text);
            try writeSpaces(writer, pad);
        }
        return;
    }

    if (width == 0) return;

    var it = std.unicode.Utf8View.init(text) catch {
        try writer.writeAll(text[0..@min(text.len, width)]);
        return;
    };
    var iter = it.iterator();

    var used: usize = 0;
    while (iter.nextCodepointSlice()) |cp_slice| {
        if (used + 1 >= width) break;
        try writer.writeAll(cp_slice);
        used += 1;
    }
    try writer.writeAll("…");
}

fn appendStyled(writer: *std.Io.Writer, codes: []const u8, value: []const u8) !void {
    if (codes.len == 0) {
        try writer.writeAll(value);
        return;
    }
    try writer.writeAll(codes);
    try writer.writeAll(value);
    try writer.writeAll(ansi.reset);
}

fn writeStyledExactly(writer: *std.Io.Writer, codes: []const u8, text: []const u8, width: usize, al: Align) !void {
    if (codes.len > 0) {
        try writer.writeAll(codes);
    }
    try writeExactly(writer, text, width, al);
    if (codes.len > 0) {
        try writer.writeAll(ansi.reset);
    }
}

fn writeSpaces(writer: *std.Io.Writer, count: usize) !void {
    for (0..count) |_| try writer.writeByte(' ');
}

//
// tests
//

test "writeExactly padding and truncation" {
    var buf: [256]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);

    try writeExactly(&writer, "12", 2, .left);
    try std.testing.expectEqualStrings("12", writer.buffered());

    writer.end = 0;
    try writeExactly(&writer, "hi", 6, .center);
    try std.testing.expectEqualStrings("  hi  ", writer.buffered());

    writer.end = 0;
    try writeExactly(&writer, "this is too long", 8, .left);
    try std.testing.expectEqualStrings("this is…", writer.buffered());

    writer.end = 0;
    try writeExactly(&writer, "éééé", 3, .left);
    try std.testing.expectEqualStrings("éé…", writer.buffered());
}

test "ascii render simple" {
    var test_table: test_support.TestTable = undefined;
    test_table.init(std.testing.allocator);
    defer test_table.deinit();

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var in = std.io.fixedBufferStream("a,b\nc,d\n");
    const records = try util.readCsv(alloc, in.reader());
    const l = try Layout.init(alloc, records, false, 80);
    defer l.deinit(alloc);
    var buf: [4096]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    test_table.table.style = style_mod.Style.init(std.testing.allocator, .never, .dark);
    test_table.table.config.row_numbers = false;
    test_table.table.config.title = "";
    var render: Render = .init(&test_table.table, &writer, l, records);
    try render.render();

    const exp =
        \\╭────┬────╮
        \\│ a  │ b  │
        \\├────┼────┤
        \\│ c  │ d  │
        \\╰────┴────╯
        \\
    ;
    try std.testing.expectEqualStrings(exp, writer.buffered());
}

test "render with title and row numbers" {
    var test_table: test_support.TestTable = undefined;
    test_table.init(std.testing.allocator);
    defer test_table.deinit();

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var in = std.io.fixedBufferStream("a,b\nc,d\n");
    const records = try util.readCsv(alloc, in.reader());
    const l = try Layout.init(alloc, records, true, 80);
    defer l.deinit(alloc);
    var buf: [4096]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    test_table.table.style = style_mod.Style.init(std.testing.allocator, .never, .dark);
    test_table.table.config.row_numbers = true;
    test_table.table.config.title = "foo";
    var render: Render = .init(&test_table.table, &writer, l, records);
    try render.render();

    try std.testing.expect(std.mem.containsAtLeast(u8, writer.buffered(), 1, "foo"));
    try std.testing.expect(std.mem.containsAtLeast(u8, writer.buffered(), 1, "│ #  │ a  │ b  │"));
    try std.testing.expect(std.mem.containsAtLeast(u8, writer.buffered(), 1, "│ 1  │ c  │ d  │"));
}

test "renderEmpty renders fallback table" {
    var test_table: test_support.TestTable = undefined;
    test_table.init(std.testing.allocator);
    defer test_table.deinit();

    var buf: [4096]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    test_table.table.style = style_mod.Style.init(std.testing.allocator, .never, .dark);
    var render: Render = .init(&test_table.table, &writer, .{ .widths = &.{} }, &.{});
    try render.render();

    const exp =
        \\╭─────────────╮
        \\│ empty table │
        \\├─────────────┤
        \\│   no data   │
        \\╰─────────────╯
        \\
    ;
    try std.testing.expectEqualStrings(exp, writer.buffered());
}

test "render uses placeholder for empty cells" {
    var test_table: test_support.TestTable = undefined;
    test_table.init(std.testing.allocator);
    defer test_table.deinit();

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var in = std.io.fixedBufferStream("a,b\n,\n");
    const records = try util.readCsv(alloc, in.reader());
    const l = try Layout.init(alloc, records, false, 80);
    defer l.deinit(alloc);
    var buf: [4096]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    test_table.table.style = style_mod.Style.init(std.testing.allocator, .never, .dark);
    var render: Render = .init(&test_table.table, &writer, l, records);
    try render.render();

    try std.testing.expect(std.mem.containsAtLeast(u8, writer.buffered(), 2, "—"));
}

const ansi = @import("ansi.zig");
const mibu = @import("mibu");
const std = @import("std");
const style_mod = @import("style.zig");
const Table = @import("table.zig").Table;
const test_support = @import("test_support.zig");
const util = @import("util.zig");
const Layout = @import("layout.zig").Layout;
