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

        // top
        if (self.border.top != .none) {
            const top = if (self.table.config.title.len > 0) spanRule(self.border.top) else self.border.top;
            try self.renderRule(top);
        }

        // title
        if (self.table.config.title.len > 0) {
            try self.renderTitle();
            if (self.border.header != .none) try self.renderRule(titleRule(self.border.top, self.border.header));
        }

        // headers
        try self.renderHeaders();
        if (self.border.header != .none) try self.renderRule(self.border.header);

        // rows
        for (0..self.table.nrows()) |row_index| {
            try self.renderRow(row_index);
            if (row_index + 1 < self.table.nrows() and self.border.row != .none) {
                try self.renderRule(self.border.row);
            }
        }

        // bottom
        if (self.border.bottom != .none) try self.renderRule(self.border.bottom);
    }

    fn renderRule(self: *Render, rule: border.BorderRule) !void {
        try self.renderRule0(rule, self.layout.widths);
    }

    // this is broken out because renderEmpty calls this
    fn renderRule0(self: *Render, rule: border.BorderRule, widths: []const usize) !void {
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
        const chrome = util.displayWidth(self.border.left) + util.displayWidth(self.border.right) + 2;
        const width = self.layout.tableWidth() - chrome;

        try self.writeChrome(self.border.left);
        try out.writeByte(' ');
        try fill(out, self.table.style().title, self.table.config.title, width, .center);
        try out.writeByte(' ');
        try self.writeChrome(self.border.right);
        try self.newline();
    }

    fn renderHeaders(self: *Render) !void {
        try self.writeChrome(self.border.left);

        var col: usize = 0;
        if (self.table.config.row_numbers) {
            try self.renderHeaderField(&col, "#");
        }
        for (self.table.columns) |column| {
            try self.renderHeaderField(&col, column.name);
        }
        try self.newline();
    }

    fn renderHeaderField(self: *Render, col: *usize, text: []const u8) !void {
        const style = self.table.style();
        const sep = if (col.* + 1 == self.layout.widths.len) self.border.right else self.border.mid;
        try self.renderField(style.headers[col.* % style.headers.len], text, col.*, sep, .left);
        col.* += 1;
    }

    fn renderRow(self: *Render, row_index: usize) !void {
        try self.writeChrome(self.border.left);

        const row_no = row_index + 1;
        var col: usize = 0;
        if (self.table.config.row_numbers) {
            var num_buf: [32]u8 = undefined;
            const label = try std.fmt.bufPrint(&num_buf, "{d}", .{row_no});
            const sep = if (col + 1 == self.layout.widths.len) self.border.right else self.border.mid;
            try self.renderField(self.table.style().chrome, label, col, sep, .right);
            col += 1;
        }

        for (self.table.columns) |column| {
            const raw = column.field(row_index);
            const is_placeholder = raw.len == 0;
            const style = self.table.style();
            const cell_style = if (is_placeholder) style.chrome else style.field;
            const field = if (is_placeholder) placeholder else raw;
            const sep = if (col + 1 == self.layout.widths.len) self.border.right else self.border.mid;
            const al: Align = switch (column.type) {
                .int, .float => .right,
                .string => .left,
            };
            try self.renderField(cell_style, field, col, sep, al);
            col += 1;
        }
        try self.newline();
    }

    //
    // empty
    //

    fn renderEmpty(self: *Render) !void {
        const style = self.table.style();
        const title = "empty table";
        const body = "no data";
        const width = @max(util.displayWidth(title), util.displayWidth(body));
        const widths = [_]usize{width};

        if (self.border.top != .none) try self.renderRule0(self.border.top, &widths);
        try self.renderEmptyRow(style.title, title, width);
        if (self.border.header != .none) try self.renderRule0(self.border.header, &widths);
        try self.renderEmptyRow(style.field, body, width);
        if (self.border.bottom != .none) try self.renderRule0(self.border.bottom, &widths);
    }

    fn renderEmptyRow(self: *Render, text_style: []const u8, text: []const u8, width: usize) !void {
        const out = &self.buf.writer;
        try self.writeChrome(self.border.left);
        try out.writeByte(' ');
        try fill(out, text_style, text, width, .center);
        try out.writeByte(' ');
        try self.writeChrome(self.border.right);
        try self.newline();
    }

    //
    // helpers
    //

    fn renderField(self: *Render, field_style: []const u8, text: []const u8, col: usize, sep: []const u8, al: Align) !void {
        const out = &self.buf.writer;
        try out.writeByte(' ');
        try fill(out, field_style, text, self.layout.widths[col], al);
        try out.writeByte(' ');
        try self.writeChrome(sep);
    }

    fn writeChrome(self: *Render, value: []const u8) !void {
        const out = &self.buf.writer;
        const chrome = self.table.style().chrome;
        if (chrome.len == 0) {
            try out.writeAll(value);
            return;
        }
        try out.writeAll(chrome);
        try out.writeAll(value);
        try out.writeAll(ansi.reset);
    }

    fn newline(self: *Render) !void {
        try self.buf.writer.writeByte('\n');
        try self.writer.writeAll(self.buf.written());
        self.buf.clearRetainingCapacity();
    }
};

//
// standalone helpers
//

fn spanRule(rule: border.BorderRule) border.BorderRule {
    return switch (rule) {
        .none => .none,
        .continuous => rule,
        .segmented => |r| .{ .continuous = .{
            .left = r.left,
            .fill = r.fill,
            .right = r.right,
        } },
    };
}

fn titleRule(top: border.BorderRule, header: border.BorderRule) border.BorderRule {
    return switch (header) {
        .none => .none,
        .continuous => header,
        .segmented => |h| switch (top) {
            .segmented => |t| .{ .segmented = .{
                .left = h.left,
                .fill = h.fill,
                .mid = t.mid,
                .right = h.right,
            } },
            else => header,
        },
    };
}

// fit text into width, using alignment. Use ansi codes if present.
fn fill(writer: *std.Io.Writer, codes: []const u8, text: []const u8, width: usize, al: Align) !void {
    if (codes.len > 0) try writer.writeAll(codes);
    defer if (codes.len > 0) writer.writeAll(ansi.reset) catch {};

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

    try util.truncate(writer, text, width);
}

fn writeSpaces(writer: *std.Io.Writer, count: usize) !void {
    for (0..count) |_| try writer.writeByte(' ');
}

test "fill padding and truncation" {
    var buf: [256]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);

    try fill(&writer, "", "12", 2, .left);
    try std.testing.expectEqualStrings("12", writer.buffered());

    writer.end = 0;
    try fill(&writer, "", "hi", 6, .center);
    try std.testing.expectEqualStrings("  hi  ", writer.buffered());

    writer.end = 0;
    try fill(&writer, "", "hi", 6, .right);
    try std.testing.expectEqualStrings("    hi", writer.buffered());
}

test "spanRule removes interior separators" {
    const rule: border.BorderRule = .{ .segmented = .{
        .left = "├",
        .fill = "─",
        .mid = "┼",
        .right = "┤",
    } };
    const out = spanRule(rule);
    try std.testing.expect(out == .continuous);
    try std.testing.expectEqualStrings("├", out.continuous.left);
    try std.testing.expectEqualStrings("─", out.continuous.fill);
    try std.testing.expectEqualStrings("┤", out.continuous.right);
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
