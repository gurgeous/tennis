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
const placeholder = "—";

const Align = enum { left, center, right };

//
// Render
//

pub const Render = struct {
    table: *Table,
    writer: *std.Io.Writer,
    layout: Layout,
    buf: std.Io.Writer.Allocating,

    pub fn init(table: *Table, writer: *std.Io.Writer, layout: Layout) Render {
        return .{
            .buf = .init(table.alloc),
            .layout = layout,
            .table = table,
            .writer = writer,
        };
    }

    pub fn deinit(self: *Render) void {
        self.buf.deinit();
    }

    //
    // main entry point
    //

    pub fn render(self: *Render) !void {
        if (self.table.isEmpty()) {
            return self.renderEmpty();
        }

        if (self.table.config.title.len > 0) {
            try self.renderSep(nw, bar, ne, bar);
            try self.renderTitle();
            try self.renderSep(w, bar, e, n);
        } else {
            try self.renderSep(nw, bar, ne, n);
        }
        try self.renderHeaders();
        try self.renderSep(w, bar, e, c);
        for (0..self.table.nrows()) |row_index| {
            try self.renderRow(row_index);
        }
        try self.renderSep(sw, bar, se, s);
    }

    //
    // render a separator line with these border chars
    //

    fn renderSep(self: *Render, left: []const u8, line: []const u8, right: []const u8, middle: []const u8) !void {
        const out = &self.buf.writer;
        const style = self.table.style();
        if (style.chrome.len > 0) {
            try out.writeAll(style.chrome);
        }
        for (self.layout.widths, 0..) |width, ii| {
            if (ii == 0) {
                try out.writeAll(left);
            } else {
                try out.writeAll(middle);
            }
            for (0..width + 2) |_| try out.writeAll(line);
        }
        try out.writeAll(right);
        if (style.chrome.len > 0) {
            try out.writeAll(ansi.reset);
        }
        try self.eol();
    }

    //
    // render title line
    //

    fn renderTitle(self: *Render) !void {
        const out = &self.buf.writer;
        const style = self.table.style();

        const chrome = 4; // <pipe><space>[...title...]<space><pipe>
        const width = self.layout.tableWidth() - chrome;

        try appendStyled(out, style.chrome, pipe);
        try out.writeByte(' ');
        try writeStyledExactly(out, style.title, self.table.config.title, width, .center);
        try out.writeByte(' ');
        try appendStyled(out, style.chrome, pipe);
        try self.eol();
    }

    //
    // headers
    //

    fn renderHeaders(self: *Render) !void {
        const out = &self.buf.writer;
        const style = self.table.style();
        try appendStyled(out, style.chrome, pipe);

        var col: usize = 0;
        if (self.table.config.row_numbers) {
            try self.renderHeaderField(out, &col, "#");
        }
        for (self.table.columns) |column| {
            try self.renderHeaderField(out, &col, column.name);
        }

        try self.eol();
    }

    fn renderHeaderField(self: *Render, out: *std.Io.Writer, col: *usize, text: []const u8) !void {
        const style = self.table.style();
        try self.renderField(out, style.headers[col.* % style.headers.len], text, col.*, .left);
        col.* += 1;
    }

    //
    // rows
    //

    fn renderRow(self: *Render, row_index: usize) !void {
        const out = &self.buf.writer;
        const style = self.table.style();
        try appendStyled(out, style.chrome, pipe);

        const row_no = row_index + 1;
        var col: usize = 0;
        if (self.table.config.row_numbers) {
            var num_buf: [32]u8 = undefined;
            const label = try std.fmt.bufPrint(&num_buf, "{d}", .{row_no});
            try self.renderField(out, style.chrome, label, col, .right);
            col += 1;
        }

        for (self.table.columns) |column| {
            const raw = column.field(row_index);
            const is_placeholder = raw.len == 0;
            const cell_style = if (is_placeholder) style.chrome else style.field;
            const field = if (is_placeholder) placeholder else raw;
            const al: Align = switch (column.type) {
                .int, .float => .right,
                .string => .left,
            };
            try self.renderField(out, cell_style, field, col, al);
            col += 1;
        }

        try self.eol();
    }

    //
    // empty
    //

    fn renderEmpty(self: *Render) !void {
        const style = self.table.style();
        const title = "empty table";
        const body = "no data";
        const width = @max(util.displayWidth(title), util.displayWidth(body));

        try self.renderEmptySep(nw, bar, ne, width);
        try self.renderEmptyRow(style.title, title, width);
        try self.renderEmptySep(w, bar, e, width);
        try self.renderEmptyRow(style.field, body, width);
        try self.renderEmptySep(sw, bar, se, width);
    }

    fn renderEmptySep(self: *Render, left: []const u8, line: []const u8, right: []const u8, width: usize) !void {
        const out = &self.buf.writer;
        const style = self.table.style();
        try appendStyled(out, style.chrome, left);
        for (0..width + 2) |_| try appendStyled(out, style.chrome, line);
        try appendStyled(out, style.chrome, right);
        try self.eol();
    }

    fn renderEmptyRow(self: *Render, text_style: []const u8, text: []const u8, width: usize) !void {
        const out = &self.buf.writer;
        const style = self.table.style();
        try appendStyled(out, style.chrome, pipe);
        try out.writeByte(' ');
        try writeStyledExactly(out, text_style, text, width, .center);
        try out.writeByte(' ');
        try appendStyled(out, style.chrome, pipe);
        try self.eol();
    }

    //
    // internal
    //

    fn eol(self: *Render) !void {
        try self.buf.writer.writeByte('\n');
        try self.writer.writeAll(self.buf.written());
        self.buf.clearRetainingCapacity();
    }

    fn renderField(self: *Render, out: *std.Io.Writer, field_style: []const u8, text: []const u8, col: usize, al: Align) !void {
        const style = self.table.style();
        try out.writeByte(' ');
        try writeStyledExactly(out, field_style, text, self.layout.widths[col], al);
        try out.writeByte(' ');
        try appendStyled(out, style.chrome, pipe);
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
        } else if (al == .right) {
            try writeSpaces(writer, pad);
            try writer.writeAll(text);
        } else {
            try writer.writeAll(text);
            try writeSpaces(writer, pad);
        }
        return;
    }

    if (width == 0) return;

    // gotta truncate. note we stop at "used + 1" to leave room for the ellipsis
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
    try test_table.init(std.testing.allocator, "a,b\nc,d\n");
    defer test_table.deinit();
    const l = try Layout.init(test_table.table);
    defer l.deinit(test_table.table.alloc);
    var buf: [4096]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    test_table.table.config.color = .off;
    test_table.table.config.theme = .dark;
    test_table.table.config.row_numbers = false;
    test_table.table.config.title = "";
    var render: Render = .init(test_table.table, &writer, l);
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
    try test_table.init(std.testing.allocator, "a,b\nc,d\n");
    defer test_table.deinit();
    var buf: [4096]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    test_table.table.config.color = .off;
    test_table.table.config.theme = .dark;
    test_table.table.config.row_numbers = true;
    test_table.table.config.title = "foo";
    const l = try Layout.init(test_table.table);
    defer l.deinit(test_table.table.alloc);
    var render: Render = .init(test_table.table, &writer, l);
    try render.render();

    try std.testing.expect(std.mem.containsAtLeast(u8, writer.buffered(), 1, "foo"));
    try std.testing.expect(std.mem.containsAtLeast(u8, writer.buffered(), 1, "│ #  │ a  │ b  │"));
    try std.testing.expect(std.mem.containsAtLeast(u8, writer.buffered(), 1, "│  1 │ c  │ d  │"));
}

test "renderEmpty renders fallback table" {
    var test_table: test_support.TestTable = undefined;
    try test_table.init(std.testing.allocator, "");
    defer test_table.deinit();

    var buf: [4096]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    test_table.table.config.color = .off;
    test_table.table.config.theme = .dark;
    const l = try Layout.init(test_table.table);
    defer l.deinit(test_table.table.alloc);
    var render: Render = .init(test_table.table, &writer, l);
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

test "render header only table falls back to empty" {
    var test_table: test_support.TestTable = undefined;
    try test_table.init(std.testing.allocator, "a,b\n");
    defer test_table.deinit();

    var buf: [4096]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    const l = try Layout.init(test_table.table);
    defer l.deinit(test_table.table.alloc);
    var render: Render = .init(test_table.table, &writer, l);
    try render.render();

    try std.testing.expect(std.mem.containsAtLeast(u8, writer.buffered(), 1, "empty table"));
}

test "render uses placeholder for empty cells" {
    var test_table: test_support.TestTable = undefined;
    try test_table.init(std.testing.allocator, "a,b\n,\n");
    defer test_table.deinit();
    var buf: [4096]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    test_table.table.config.color = .off;
    test_table.table.config.theme = .dark;
    const l = try Layout.init(test_table.table);
    defer l.deinit(test_table.table.alloc);
    var render: Render = .init(test_table.table, &writer, l);
    try render.render();

    try std.testing.expect(std.mem.containsAtLeast(u8, writer.buffered(), 2, "—"));
}

test "render headers does not use placeholder for empty header cell" {
    var test_table: test_support.TestTable = undefined;
    try test_table.init(std.testing.allocator, "a,\n1,2\n");
    defer test_table.deinit();
    var buf: [4096]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    test_table.table.config.color = .off;
    const l = try Layout.init(test_table.table);
    defer l.deinit(test_table.table.alloc);
    var render: Render = .init(test_table.table, &writer, l);
    try render.render();

    try std.testing.expect(std.mem.containsAtLeast(u8, writer.buffered(), 1, "│ a  │    │"));
    try std.testing.expect(std.mem.containsAtLeast(u8, writer.buffered(), 1, "│  1 │  2 │"));
}

const ansi = @import("ansi.zig");
const Layout = @import("layout.zig").Layout;
const Row = @import("types.zig").Row;
const std = @import("std");
const Table = @import("table.zig").Table;
const test_support = @import("test_support.zig");
const util = @import("util.zig");
