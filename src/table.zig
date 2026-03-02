pub const Table = struct {
    // passed into init
    alloc: std.mem.Allocator,
    config: types.Config = .{},
    // calculated from config + terminal
    style: Style = .{},
    term_width: usize = 0,

    pub fn init(alloc: std.mem.Allocator, config: types.Config) Table {
        return .{
            .alloc = alloc,
            .config = config,
            .style = Style.init(alloc, config.color, config.theme),
            .term_width = if (config.width > 0) config.width else util.termWidth(),
        };
    }

    pub fn render(self: *Table, records: [][][]const u8, writer: *std.Io.Writer) !void {
        const layout = try Layout.init(self.alloc, records, self.config.row_numbers, self.term_width);
        defer layout.deinit(self.alloc);

        var renderer: Render = .init(self, writer, layout, records);
        try renderer.render();
    }
};

const render_mod = @import("render.zig");
const std = @import("std");
const Layout = @import("layout.zig").Layout;
const Style = @import("style.zig").Style;
const Render = render_mod.Render;
const types = @import("types.zig");
const util = @import("util.zig");
