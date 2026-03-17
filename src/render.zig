const placeholder = "—";

const Align = enum { left, center, right };

pub const Render = struct {
    border: border.Border,
    table: *Table,
    writer: *std.Io.Writer,
    layout: Layout,
    buf: std.Io.Writer.Allocating,

    pub fn init(table: *Table, writer: *std.Io.Writer, layout: Layout) Render {
        return .{
            .border = border.getBorder(table.config.border),
            .buf = .init(table.alloc),
            .layout = layout,
            .table = table,
            .writer = writer,
        };
    }

    pub fn deinit(self: *Render) void {
        self.buf.deinit();
    }

    pub fn render(self: *Render) !void {
        if (self.table.isEmpty()) {
            return self.renderEmpty();
        }

        if (self.border.top != .none) try self.renderSep(self.border.top, self.layout.widths);
        if (self.table.config.title.len > 0) {
            try self.renderTitle();
            if (self.border.header != .none) try self.renderSep(self.border.header, self.layout.widths);
        }
        try self.renderHeaders();
        if (self.border.header != .none) try self.renderSep(self.border.header, self.layout.widths);
        for (0..self.table.nrows()) |row_index| {
            try self.renderRow(row_index);
            if (row_index + 1 < self.table.nrows() and self.border.row != .none) {
                try self.renderSep(self.border.row, self.layout.widths);
            }
        }
        if (self.border.bottom != .none) try self.renderSep(self.border.bottom, self.layout.widths);
    }

    fn renderSep(self: *Render, rule: border.BorderRule, widths: []const usize) !void {
        const out = &self.buf.writer;
        const style = self.table.style();
        if (style.chrome.len > 0) try out.writeAll(style.chrome);
        switch (rule) {
            .none => {},
            .continuous => |r| {
                try out.writeAll(r.left);
                const total_width = util.sum(usize, widths) + 2 * widths.len + util.displayWidth(self.border.mid) * (widths.len -| 1);
                for (0..total_width) |_| try out.writeAll(r.fill);
                try out.writeAll(r.right);
            },
            .segmented => |r| {
                for (widths, 0..) |width, ii| {
                    try out.writeAll(if (ii == 0) r.left else r.mid);
                    for (0..width + 2) |_| try out.writeAll(r.fill);
                }
                try out.writeAll(r.right);
            },
        }
        if (style.chrome.len > 0) try out.writeAll(ansi.reset);
        try self.newline();
    }

    fn renderTitle(self: *Render) !void {
        const out = &self.buf.writer;
        const style = self.table.style();
        const chrome = util.displayWidth(self.border.left) + util.displayWidth(self.border.right) + 2;
        const width = self.layout.tableWidth() - chrome;

        try appendStyled(out, style.chrome, self.border.left);
        try out.writeByte(' ');
        try writeStyledExactly(out, style.title, self.table.config.title, width, .center);
        try out.writeByte(' ');
        try appendStyled(out, style.chrome, self.border.right);
        try self.newline();
    }

    fn renderHeaders(self: *Render) !void {
        const out = &self.buf.writer;
        const style = self.table.style();
        try appendStyled(out, style.chrome, self.border.left);

        var col: usize = 0;
        if (self.table.config.row_numbers) {
            try self.renderHeaderField(out, &col, "#");
        }
        for (self.table.columns) |column| {
            try self.renderHeaderField(out, &col, column.name);
        }
        try self.newline();
    }

    fn renderHeaderField(self: *Render, out: *std.Io.Writer, col: *usize, text: []const u8) !void {
        const style = self.table.style();
        const sep = if (col.* + 1 == self.layout.widths.len) self.border.right else self.border.mid;
        try self.renderField(out, style.headers[col.* % style.headers.len], text, col.*, sep, .left);
        col.* += 1;
    }

    fn renderRow(self: *Render, row_index: usize) !void {
        const out = &self.buf.writer;
        const style = self.table.style();
        try appendStyled(out, style.chrome, self.border.left);

        const row_no = row_index + 1;
        var col: usize = 0;
        if (self.table.config.row_numbers) {
            var num_buf: [32]u8 = undefined;
            const label = try std.fmt.bufPrint(&num_buf, "{d}", .{row_no});
            const sep = if (col + 1 == self.layout.widths.len) self.border.right else self.border.mid;
            try self.renderField(out, style.chrome, label, col, sep, .right);
            col += 1;
        }

        for (self.table.columns) |column| {
            const raw = column.field(row_index);
            const is_placeholder = raw.len == 0;
            const cell_style = if (is_placeholder) style.chrome else style.field;
            const field = if (is_placeholder) placeholder else raw;
            const sep = if (col + 1 == self.layout.widths.len) self.border.right else self.border.mid;
            const al: Align = switch (column.type) {
                .int, .float => .right,
                .string => .left,
            };
            try self.renderField(out, cell_style, field, col, sep, al);
            col += 1;
        }
        try self.newline();
    }

    fn renderEmpty(self: *Render) !void {
        const style = self.table.style();
        const title = "empty table";
        const body = "no data";
        const width = @max(util.displayWidth(title), util.displayWidth(body));
        const widths = [_]usize{width};

        if (self.border.top != .none) try self.renderSep(self.border.top, &widths);
        try self.renderEmptyRow(style.title, title, width);
        if (self.border.header != .none) try self.renderSep(self.border.header, &widths);
        try self.renderEmptyRow(style.field, body, width);
        if (self.border.bottom != .none) try self.renderSep(self.border.bottom, &widths);
    }

    fn renderEmptyRow(self: *Render, text_style: []const u8, text: []const u8, width: usize) !void {
        const out = &self.buf.writer;
        const style = self.table.style();
        try appendStyled(out, style.chrome, self.border.left);
        try out.writeByte(' ');
        try writeStyledExactly(out, text_style, text, width, .center);
        try out.writeByte(' ');
        try appendStyled(out, style.chrome, self.border.right);
        try self.newline();
    }

    fn newline(self: *Render) !void {
        try self.buf.writer.writeByte('\n');
        try self.writer.writeAll(self.buf.written());
        self.buf.clearRetainingCapacity();
    }

    fn renderField(self: *Render, out: *std.Io.Writer, field_style: []const u8, text: []const u8, col: usize, sep: []const u8, al: Align) !void {
        const style = self.table.style();
        try out.writeByte(' ');
        try writeStyledExactly(out, field_style, text, self.layout.widths[col], al);
        try out.writeByte(' ');
        try appendStyled(out, style.chrome, sep);
    }
};

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
    if (codes.len > 0) try writer.writeAll(codes);
    try writeExactly(writer, text, width, al);
    if (codes.len > 0) try writer.writeAll(ansi.reset);
}

fn writeSpaces(writer: *std.Io.Writer, count: usize) !void {
    for (0..count) |_| try writer.writeByte(' ');
}

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

test "render basic border" {
    var test_table: test_support.TestTable = undefined;
    try test_table.init(std.testing.allocator, "a,b\nc,d\n");
    defer test_table.deinit();
    const l = try Layout.init(test_table.table);
    defer l.deinit(test_table.table.alloc);
    var buf: [4096]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    test_table.table.config.border = .basic;
    test_table.table.config.color = .off;
    var render: Render = .init(test_table.table, &writer, l);
    try render.render();

    const exp =
        \\+----+----+
        \\| a  | b  |
        \\+----+----+
        \\| c  | d  |
        \\+----+----+
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
const border = @import("border.zig");
const Layout = @import("layout.zig").Layout;
const std = @import("std");
const Table = @import("table.zig").Table;
const test_support = @import("test_support.zig");
const util = @import("util.zig");
