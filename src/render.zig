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
    reset: []const u8 = "",
    reset_buf: [128]u8 = undefined,

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
        if (self.table.isEmpty()) return self.renderEmpty();

        // top rule
        if (self.border.top != .none) {
            const top = if (self.table.config.title.len > 0 or self.table.config.footer.len > 0) spanRule(self.border.top) else self.border.top;
            try self.renderRule(top);
        }

        // title and title rule
        if (self.table.config.title.len > 0) {
            try self.renderTitle();
            if (self.border.header != .none) try self.renderRule(titleRule(self.border.top, self.border.header));
        }

        // headers and header rule
        try self.renderHeaders();
        if (self.border.header != .none) try self.renderRule(self.border.header);

        // rows
        for (0..self.table.nrows()) |index| {
            try self.renderRow(index);
            if (index + 1 < self.table.nrows() and self.border.row != .none) {
                try self.renderRule(self.border.row);
            }
        }

        // footer and footer rule
        if (self.table.config.footer.len > 0) {
            const footer_top = if (self.border.row != .none)
                footerRule(self.border.row, self.border.bottom)
            else
                footerRule(self.border.header, self.border.bottom);
            if (footer_top != .none) try self.renderRule(footer_top);
            try self.renderFooter();
        }

        // bottom rule
        if (self.border.bottom != .none) {
            const bottom = if (self.table.config.footer.len > 0) spanRule(self.border.bottom) else self.border.bottom;
            try self.renderRule(bottom);
        }
    }

    //
    // rules
    //

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
        try self.newline();
    }

    //
    // Render the optional table title row and its surrounding rules.
    //

    fn renderTitle(self: *Render) !void {
        const out = &self.buf.writer;
        const chromeWidth = doomicode.displayWidth(self.border.left) + doomicode.displayWidth(self.border.right) + 2;
        const width = self.layout.tableWidth() - chromeWidth;

        try self.writeChrome(self.border.left);
        try out.writeByte(' ');
        try fill(out, self.table.style().title, true, "", self.table.config.title, width, .center);
        try out.writeByte(' ');
        try self.writeChrome(self.border.right);
        try self.newline();
    }

    // Render the optional full-width footer row.
    fn renderFooter(self: *Render) !void {
        const out = &self.buf.writer;
        const chromeWidth = doomicode.displayWidth(self.border.left) + doomicode.displayWidth(self.border.right) + 2;
        const width = self.layout.tableWidth() - chromeWidth;

        try self.writeChrome(self.border.left);
        try out.writeByte(' ');
        try fill(out, self.table.style().chrome, false, "", self.table.config.footer, width, .center);
        try out.writeByte(' ');
        try self.writeChrome(self.border.right);
        try self.newline();
    }

    //
    // Render the header row.
    //

    fn renderHeaders(self: *Render) !void {
        try self.writeChrome(self.border.left);

        var col: usize = 0;
        if (self.table.config.row_numbers) {
            try self.renderHeaderField(col, "#");
            col += 1;
        }
        for (self.table.columns) |column| {
            try self.renderHeaderField(col, column.name);
            col += 1;
        }
        try self.newline();
    }

    // Render one header cell and advance the output column.
    fn renderHeaderField(self: *Render, col: usize, text: []const u8) !void {
        const style = self.table.style();
        const sep = if (col + 1 == self.layout.widths.len) self.border.right else self.border.mid;
        try self.renderField(style.headers[col % style.headers.len], true, text, col, sep, .left);
    }

    //
    // Render one visible data row.
    //

    fn renderRow(self: *Render, index: usize) !void {
        // calculate row "reset" which is ansi.reset + zebra, if any
        const style = self.table.style();
        if (style.chrome.len > 0) {
            const zebra = self.table.config.zebra and index % 2 == 0;
            const zebra_style = if (zebra) style.zebra else "";
            self.reset = try std.fmt.bufPrint(&self.reset_buf, "{s}{s}", .{ ansi.reset, zebra_style });
            try self.buf.writer.writeAll(self.reset);
        }

        // left
        try self.writeChrome(self.border.left);

        // row #
        var col: usize = 0;
        if (self.table.config.row_numbers) {
            var num_buf: [32]u8 = undefined;
            const label = try std.fmt.bufPrint(&num_buf, "{d}", .{index + 1});
            const sep = if (col + 1 == self.layout.widths.len) self.border.right else self.border.mid;
            try self.renderField(style.chrome, false, label, col, sep, .right);
            col += 1;
        }

        // fields
        for (self.table.columns) |column| {
            const str = column.field(index);
            const is_placeholder = str.len == 0;
            const cell_style = if (is_placeholder)
                style.chrome
            else switch (column.type) {
                .int, .float, .percent => style.headers[col % style.headers.len],
                .string => style.field,
            };
            const field = if (is_placeholder) placeholder else str;
            const sep = if (col + 1 == self.layout.widths.len) self.border.right else self.border.mid;
            const al: Align = switch (column.type) {
                .int, .float, .percent => .right,
                .string => .left,
            };
            try self.renderField(cell_style, false, field, col, sep, al);
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
        try fill(out, text_style, false, "", text, width, .center);
        try out.writeByte(' ');
        try self.writeChrome(self.border.right);
        try self.newline();
    }

    //
    // helpers
    //

    // Render one cell followed by its separator.
    fn renderField(self: *Render, field_style: []const u8, is_bold: bool, text: []const u8, col: usize, sep: []const u8, al: Align) !void {
        const out = &self.buf.writer;
        try out.writeByte(' ');
        try fill(out, field_style, is_bold, self.reset, text, self.layout.widths[col], al);
        try out.writeByte(' ');
        try self.writeChrome(sep);
    }

    // Write table chrome using the configured chrome style.
    fn writeChrome(self: *Render, value: []const u8) !void {
        const out = &self.buf.writer;
        const chrome = self.table.style().chrome;
        if (chrome.len > 0) try out.writeAll(chrome);
        try out.writeAll(value);
        if (chrome.len > 0) try out.writeAll(self.reset);
    }

    // Finish the buffered line and flush it to the real writer.
    fn newline(self: *Render) !void {
        if (self.table.style().chrome.len > 0) try self.buf.writer.writeAll(ansi.reset);
        try self.buf.writer.writeByte('\n');
        try self.writer.writeAll(self.buf.written());
        self.buf.clearRetainingCapacity();
        self.reset = "";
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

// Choose the footer separator rule between the last row rule and the bottom rule.
fn footerRule(row: border.BorderRule, bottom: border.BorderRule) border.BorderRule {
    return switch (row) {
        .none => .none,
        .continuous => row,
        .segmented => |r| switch (bottom) {
            .segmented => |b| .{ .segmented = .{
                .left = r.left,
                .fill = r.fill,
                .mid = b.mid,
                .right = r.right,
            } },
            else => row,
        },
    };
}

// Write one aligned cell, truncating and padding as needed.
fn fill(writer: *std.Io.Writer, codes: []const u8, is_bold: bool, reset: []const u8, text: []const u8, width: usize, al: Align) !void {
    const has_ansi = codes.len > 0;
    if (is_bold and has_ansi) try writer.writeAll(ansi.bold);
    if (has_ansi) try writer.writeAll(codes);
    defer if (has_ansi) {
        writer.writeAll(if (reset.len > 0) reset else ansi.reset) catch {};
    };

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
    const spaces = "                                ";
    var left = count;
    while (left > 0) {
        const n = @min(left, spaces.len);
        try writer.writeAll(spaces[0..n]);
        left -= n;
    }
}

//
// testing
//

test "fill padding and truncation" {
    var buf: [256]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);

    try fill(&writer, "", false, "", "12", 2, .left);
    try testing.expectEqualStrings("12", writer.buffered());

    writer.end = 0;
    try fill(&writer, "", false, "", "hi", 6, .center);
    try testing.expectEqualStrings("  hi  ", writer.buffered());

    writer.end = 0;
    try fill(&writer, "", false, "", "hi", 6, .right);
    try testing.expectEqualStrings("    hi", writer.buffered());
}

test "fill can add bold before the color codes" {
    var buf: [256]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    try fill(&writer, "\x1b[38;2;1;2;3m", true, "", "x", 1, .left);
    try testing.expectEqualStrings("\x1b[1m\x1b[38;2;1;2;3mx\x1b[0m", writer.buffered());
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
    try test_table.init(testing.allocator, .{}, "a,b\nc,d\n");
    defer test_table.deinit();
    var buf: [4096]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    test_table.table.config.color = .off;
    test_table.table.config.theme = .dark;
    test_table.table.config.row_numbers = true;
    test_table.table.config.title = try test_table.table.alloc.dupe(u8, "foo");
    const l = try Layout.init(test_table.table);
    defer l.deinit(test_table.table.alloc);
    var render: Render = .init(test_table.table, &writer, l);
    defer render.deinit();
    try render.render();

    try testing.expect(std.mem.containsAtLeast(u8, writer.buffered(), 1, "foo"));
    try testing.expect(std.mem.containsAtLeast(u8, writer.buffered(), 1, "│ #  │ a  │ b  │"));
    try testing.expect(std.mem.containsAtLeast(u8, writer.buffered(), 1, "│  1 │ c  │ d  │"));
}

test "render right-aligns percent columns" {
    const got = try renderTest("name,score\nalice,12%\nbob,-3.5%\n", .{ .color = .off, .width = .{ .chars = 80 } });
    defer testing.allocator.free(got);

    try testing.expect(std.mem.indexOf(u8, got, "alice │   12% │") != null);
    try testing.expect(std.mem.indexOf(u8, got, "bob   │ -3.5% │") != null);
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

test "render zebra uses alternating row background" {
    const out = try renderTest("a,b\nc,d\ne,f\n", .{ .zebra = true, .theme = .dark });
    defer testing.allocator.free(out);
    const zebra = "\x1b[38;2;255;255;255;48;2;34;34;34m";
    try testing.expect(std.mem.containsAtLeast(u8, out, 1, zebra));
    try testing.expect(std.mem.containsAtLeast(u8, out, 1, zebra ++ "\x1b[38;2;107;114;128m"));
    try testing.expect(std.mem.containsAtLeast(u8, out, 1, ansi.reset ++ zebra));
}

fn renderTest(input: []const u8, config: types.Config) ![]u8 {
    var test_table: test_support.TestTable = undefined;
    try test_table.init(testing.allocator, .{}, input);
    defer test_table.deinit();
    try applyRenderConfig(test_table.table, config);
    const l = try Layout.init(test_table.table);
    defer l.deinit(test_table.table.alloc);
    var buf: [4096]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    var render: Render = .init(test_table.table, &writer, l);
    defer render.deinit();
    try render.render();
    return testing.allocator.dupe(u8, writer.buffered());
}

fn applyRenderConfig(table: *Table, config: types.Config) !void {
    table.config.border = config.border;
    table.config.color = config.color;
    table.config.theme = config.theme;
    table.config.row_numbers = config.row_numbers;
    if (config.title.len > 0) table.config.title = try table.alloc.dupe(u8, config.title);
    if (config.footer.len > 0) table.config.footer = try table.alloc.dupe(u8, config.footer);
    table.config.zebra = config.zebra;
    table.config.width = config.width;
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
