pub const Table = struct {
    // passed into init
    alloc: std.mem.Allocator,
    csv: Csv,
    config: types.Config = .{},
    // calculated from config + terminal
    style_cache: ?Style = null,
    term_width: ?usize = null,

    //
    // init/deinit
    //

    pub fn init(alloc: std.mem.Allocator, config: types.Config, reader: anytype) !Table {
        return .{
            .alloc = alloc,
            .csv = try Csv.init(alloc, reader),
            .config = config,
        };
    }

    pub fn deinit(self: *Table) void {
        self.csv.deinit(self.alloc);
    }

    //
    // main
    //

    pub fn renderTable(self: *Table, writer: *std.Io.Writer) !void {
        const layout = try Layout.init(self.alloc, self.csv.rows, self.config.row_numbers, self.termWidth());
        defer layout.deinit(self.alloc);

        var renderer: Render = .init(self, writer, layout, self.csv.rows);
        defer renderer.deinit();
        try renderer.render();
    }

    //
    // memoized accessors
    //

    pub fn termWidth(self: *Table) usize {
        if (self.term_width == null) {
            self.term_width = if (self.config.width > 0) self.config.width else util.termWidth();
        }
        return self.term_width.?;
    }

    pub fn style(self: *Table) *const Style {
        if (self.style_cache == null) {
            self.style_cache = Style.init(self.alloc, self.config.color, self.config.theme);
        }
        return &self.style_cache.?;
    }
};

const Csv = @import("csv.zig").Csv;
const Layout = @import("layout.zig").Layout;
const Render = @import("render.zig").Render;
const std = @import("std");
const Style = @import("style.zig").Style;
const types = @import("types.zig");
const util = @import("util.zig");
