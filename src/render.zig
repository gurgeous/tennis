// Render a table into a terminal-oriented boxed layout.
const placeholder = "—";

// Horizontal alignment modes for rendered cells.
const Align = enum { left, center, right };

// Stateful table renderer with one buffered output line.
pub const Render = struct {
    border: border.Border,
    table: *Table,
    writer: *std.Io.Writer,
    layout: Layout,
    buf: std.Io.Writer.Allocating,

    // Build a renderer around a table, writer, and computed layout.
    pub fn init(table: *Table, writer: *std.Io.Writer, layout: Layout) Render {
        return .{
            .border = border.getBorder(table.config.border),
            .buf = .init(table.alloc),
            .layout = layout,
            .table = table,
            .writer = writer,
        };
    }

    // Release renderer-owned scratch buffers.
    pub fn deinit(self: *Render) void {
        self.buf.deinit();
    }

    // Write the full table output.
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
        for (0..self.table.nrows()) |visible_index| {
            try self.renderRow(visible_index);
            if (visible_index + 1 < self.table.nrows() and self.border.row != .none) {
                try self.renderRule(self.border.row);
            }
        }

        // bottom
        if (self.border.bottom != .none) try self.renderRule(self.border.bottom);
    }

    // Render one horizontal border rule using the table layout widths.
    fn renderRule(self: *Render, rule: border.BorderRule) !void {
        try self.renderRule0(rule, self.layout.widths);
    }

    // Render one horizontal border rule using explicit widths.
    fn renderRule0(self: *Render, rule: border.BorderRule, widths: []const usize) !void {
        const out = &self.buf.writer;
        const style = self.table.style();
        if (style.chrome.len > 0) try out.writeAll(style.chrome);
        switch (rule) {
            .none => {},
            .continuous => |r| {
                try out.writeAll(r.left);
                const total_width = util.sum(usize, widths) + 2 * widths.len + doomicode.displayWidth(self.border.mid) * (widths.len -| 1);
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

    // Render the optional table title row and its surrounding rules.
    fn renderTitle(self: *Render) !void {
        const out = &self.buf.writer;
        const chrome = doomicode.displayWidth(self.border.left) + doomicode.displayWidth(self.border.right) + 2;
        const width = self.layout.tableWidth() - chrome;

        try self.writeChrome(self.border.left);
        try out.writeByte(' ');
        try fill(out, self.table.style().title, self.table.config.title, width, .center);
        try out.writeByte(' ');
        try self.writeChrome(self.border.right);
        try self.newline();
    }

    // Render the header row.
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

    // Render one header cell and advance the output column.
    fn renderHeaderField(self: *Render, col: *usize, text: []const u8) !void {
        const style = self.table.style();
        const sep = if (col.* + 1 == self.layout.widths.len) self.border.right else self.border.mid;
        try self.renderField(style.headers[col.* % style.headers.len], text, col.*, sep, .left);
        col.* += 1;
    }

    // Render one visible data row.
    fn renderRow(self: *Render, visible_index: usize) !void {
        try self.writeChrome(self.border.left);

        var col: usize = 0;
        if (self.table.config.row_numbers) {
            var num_buf: [32]u8 = undefined;
            const label = try std.fmt.bufPrint(&num_buf, "{d}", .{visible_index + 1});
            const sep = if (col + 1 == self.layout.widths.len) self.border.right else self.border.mid;
            try self.renderField(self.table.style().chrome, label, col, sep, .right);
            col += 1;
        }

        for (self.table.columns) |column| {
            const raw = column.field(visible_index);
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

    // Render the empty-table placeholder output.
    fn renderEmpty(self: *Render) !void {
        const style = self.table.style();
        const title = "empty table";
        const body = "no data";
        const width = @max(doomicode.displayWidth(title), doomicode.displayWidth(body));
        const widths = [_]usize{width};

        if (self.border.top != .none) try self.renderRule0(self.border.top, &widths);
        try self.renderEmptyRow(style.title, title, width);
        if (self.border.header != .none) try self.renderRule0(self.border.header, &widths);
        try self.renderEmptyRow(style.field, body, width);
        if (self.border.bottom != .none) try self.renderRule0(self.border.bottom, &widths);
    }

    // Render one full-width placeholder row.
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

    // Render one cell followed by its separator.
    fn renderField(self: *Render, field_style: []const u8, text: []const u8, col: usize, sep: []const u8, al: Align) !void {
        const out = &self.buf.writer;
        try out.writeByte(' ');
        try fill(out, field_style, text, self.layout.widths[col], al);
        try out.writeByte(' ');
        try self.writeChrome(sep);
    }

    // Write table chrome using the configured chrome style.
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

    // Finish the buffered line and flush it to the real writer.
    fn newline(self: *Render) !void {
        try self.buf.writer.writeByte('\n');
        try self.writer.writeAll(self.buf.written());
        self.buf.clearRetainingCapacity();
    }
};

//
// standalone helpers
//

// Convert a rule into a spanning single-cell rule.
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

// Choose the title separator rule between the top and header rules.
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

// Write one aligned cell, truncating and padding as needed.
fn fill(writer: *std.Io.Writer, codes: []const u8, text: []const u8, width: usize, al: Align) !void {
    if (codes.len > 0) try writer.writeAll(codes);
    defer if (codes.len > 0) writer.writeAll(ansi.reset) catch {};

    const display_width = doomicode.displayWidth(text);
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

    try doomicode.truncate(writer, text, width);
}

// Write a run of ASCII spaces.
fn writeSpaces(writer: *std.Io.Writer, count: usize) !void {
    for (0..count) |_| try writer.writeByte(' ');
}

//
// testing
//

test "fill padding and truncation" {
    var buf: [256]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);

    try fill(&writer, "", "12", 2, .left);
    try testing.expectEqualStrings("12", writer.buffered());

    writer.end = 0;
    try fill(&writer, "", "hi", 6, .center);
    try testing.expectEqualStrings("  hi  ", writer.buffered());

    writer.end = 0;
    try fill(&writer, "", "hi", 6, .right);
    try testing.expectEqualStrings("    hi", writer.buffered());
}

test "spanRule removes interior separators" {
    const rule: border.BorderRule = .{ .segmented = .{
        .left = "├",
        .fill = "─",
        .mid = "┼",
        .right = "┤",
    } };
    const out = spanRule(rule);
    try testing.expect(out == .continuous);
    try testing.expectEqualStrings("├", out.continuous.left);
    try testing.expectEqualStrings("─", out.continuous.fill);
    try testing.expectEqualStrings("┤", out.continuous.right);
}

test "render exact outputs" {
    const cases = [_]struct {
        name: []const u8,
        input: []const u8,
        config: types.Config,
        want: []const u8,
    }{
        .{
            .name = "ascii",
            .input = "a,b\nc,d\n",
            .config = .{ .color = .off, .theme = .dark },
            .want =
            \\╭────┬────╮
            \\│ a  │ b  │
            \\├────┼────┤
            \\│ c  │ d  │
            \\╰────┴────╯
            \\
            ,
        },
        .{
            .name = "basic",
            .input = "a,b\nc,d\n",
            .config = .{ .border = .basic, .color = .off },
            .want =
            \\+----+----+
            \\| a  | b  |
            \\+----+----+
            \\| c  | d  |
            \\+----+----+
            \\
            ,
        },
        .{
            .name = "empty",
            .input = "",
            .config = .{ .color = .off, .theme = .dark },
            .want =
            \\╭─────────────╮
            \\│ empty table │
            \\├─────────────┤
            \\│   no data   │
            \\╰─────────────╯
            \\
            ,
        },
    };

    for (cases) |tc| {
        const got = try renderTest(tc.input, tc.config);
        defer testing.allocator.free(got);
        try testing.expectEqualStrings(tc.want, got);
    }
}

test "render with title and row numbers" {
    var test_table: test_support.TestTable = undefined;
    try test_table.init(testing.allocator, "a,b\nc,d\n");
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

    try testing.expect(std.mem.containsAtLeast(u8, writer.buffered(), 1, "foo"));
    try testing.expect(std.mem.containsAtLeast(u8, writer.buffered(), 1, "│ #  │ a  │ b  │"));
    try testing.expect(std.mem.containsAtLeast(u8, writer.buffered(), 1, "│  1 │ c  │ d  │"));
}

test "render header only table falls back to empty" {
    const out = try renderTest("a,b\n", .{});
    defer testing.allocator.free(out);
    try testing.expect(std.mem.containsAtLeast(u8, out, 1, "empty table"));
}

test "render content cases" {
    const cases = [_]struct {
        input: []const u8,
        config: types.Config,
        needles: []const []const u8,
    }{
        .{ .input = "a,b\n,\n", .config = .{ .color = .off, .theme = .dark }, .needles = &.{ "—", "—" } },
        .{ .input = "a,\n1,2\n", .config = .{ .color = .off }, .needles = &.{ "│ a  │    │", "│  1 │  2 │" } },
    };

    for (cases) |tc| {
        const out = try renderTest(tc.input, tc.config);
        defer testing.allocator.free(out);
        for (tc.needles) |needle| try testing.expect(std.mem.containsAtLeast(u8, out, 1, needle));
    }
}

fn renderTest(input: []const u8, config: types.Config) ![]u8 {
    var test_table: test_support.TestTable = undefined;
    try test_table.init(testing.allocator, input);
    defer test_table.deinit();
    applyRenderConfig(test_table.table, config);
    const l = try Layout.init(test_table.table);
    defer l.deinit(test_table.table.alloc);
    var buf: [4096]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    var render: Render = .init(test_table.table, &writer, l);
    try render.render();
    return testing.allocator.dupe(u8, writer.buffered());
}

fn applyRenderConfig(table: *Table, config: types.Config) void {
    table.config.border = config.border;
    table.config.color = config.color;
    table.config.theme = config.theme;
    table.config.row_numbers = config.row_numbers;
    table.config.title = config.title;
    if (config.width > 0) table.config.width = config.width;
}

const ansi = @import("ansi.zig");
const border = @import("border.zig");
const doomicode = @import("doomicode.zig");
const Layout = @import("layout.zig").Layout;
const std = @import("std");
const testing = std.testing;
const Table = @import("table.zig").Table;
const test_support = @import("test_support.zig");
const types = @import("types.zig");
const util = @import("util.zig");
