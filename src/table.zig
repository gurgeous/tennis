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

    pub fn renderTable(self: *Table, records: [][][]const u8, writer: *std.Io.Writer) !void {
        const layout = try Layout.init(self.alloc, records, self.config.row_numbers, self.term_width);
        defer layout.deinit(self.alloc);

        var renderer: Render = .init(self, writer, layout, records);
        defer renderer.deinit();
        try renderer.render();
    }
};

const Layout = @import("layout.zig").Layout;
const Render = @import("render.zig").Render;
const std = @import("std");
const Style = @import("style.zig").Style;
const types = @import("types.zig");
const util = @import("util.zig");
