//
// Glossary:
//   natural    Measured full width of a column, including header and fields.
//   floor      Lower bound used by autolayout.
//   ceil       Upper bound used by autolayout; usually below natural.
//   basis      Like flex-basis. Usually 1, but -b can increase.
//   budget     Data-field width available after borders and slack.
//   expansion  Post-autolayout increase due to -bb or -bbb.
//
// TLDR - measure natural column widths, build floor/ceil range for each column,
// then distribute the terminal-width budget across those ranges. AutoLayout
// stays within budget. Plain -b only changes basis and still fits.
//
// -bb/-bbb expansions apply AFTER autolayout and may make the rendered table
// wider than termwidth.
//

const width_fudge = 2;

//
// simple struct to contain the results of layout
//

pub const Layout = struct {
    widths: []const usize,

    pub fn init(table: *Table) !Layout {
        // early exits to avoid AutoLayout
        if (table.isEmpty()) return .{ .widths = try table.app.alloc.alloc(usize, 0) };
        if (table.config.width == .min) return .{ .widths = try measure(table, .headers) };
        if (table.config.width == .max) return .{ .widths = try measure(table, .fields) };

        // AutoLayout, the main event!
        var auto = try AutoLayout.init(table);
        defer auto.deinit();
        return .{ .widths = try auto.run() };
    }

    pub fn deinit(self: Layout, alloc: std.mem.Allocator) void {
        alloc.free(self.widths);
    }

    // Data width is only printable field content, not borders or padding.
    pub fn dataWidth(self: Layout) usize {
        return util.sum(usize, self.widths);
    }

    // Chrome is the table border, separators, and spacing around fields.
    pub fn chromeWidth(self: Layout) usize {
        return calcChromeWidth(self.widths.len);
    }

    // full table width, including chrome
    pub fn tableWidth(self: Layout) usize {
        return self.chromeWidth() + self.dataWidth();
    }
};

fn calcChromeWidth(ncols: usize) usize {
    return ncols * 3 + 1;
}

//
// internal AutoLayout calculation
//

const AutoLayout = struct {
    alloc: std.mem.Allocator,
    budget: usize = 0,
    cols: []AutoCol = &.{},
    synthetic: usize = 0, // 1 if row numbers
    table: *Table,

    fn init(table: *Table) !AutoLayout {
        const alloc = table.app.alloc;

        // calc natural (full) width of each col
        const natural = try measure(table, .fields);
        defer alloc.free(natural);

        var self: AutoLayout = .{
            .alloc = alloc,
            .budget = table.termWidth() -| (calcChromeWidth(natural.len) + width_fudge),
            .synthetic = if (table.config.row_numbers) 1 else 0,
            .table = table,
        };
        errdefer self.deinit();

        self.cols = try AutoCol.initAll(alloc, natural);
        return self;
    }

    fn deinit(self: *AutoLayout) void {
        self.alloc.free(self.cols);
    }

    // If natural widths fit, skip truncation and preserve full values.
    fn run(self: *AutoLayout) ![]usize {
        // Validate -b/-bb/-bbb before the natural-fit exit so invalid columns
        // fail consistently, even when no truncation is needed.
        try self.buildBig();

        // early exit if we fit easily
        if (self.budget >= AutoCol.sum(self.cols, .natural)) {
            return try AutoCol.dupe(self.alloc, self.cols, .natural);
        }

        // inputs
        self.buildFloor();
        self.buildCeil();
        self.buildBasis();

        // autolayout
        const widths = try self.allocate();
        errdefer self.alloc.free(widths);

        // -bb and -bbb are expansions: apply them after autolayout, even if the
        // rendered table becomes wider than the terminal.
        try self.bigger(widths);

        return widths;
    }

    //
    // big handling
    //

    fn buildBig(self: *AutoLayout) !void {
        // If a column appears in multiple big flags, keep the strongest level.
        try self.applyBig(self.table.config.big1, 1);
        try self.applyBig(self.table.config.big2, 2);
        try self.applyBig(self.table.config.big3, 3);
    }

    fn applyBig(self: *AutoLayout, spec: []const u8, level: usize) !void {
        const cols = types.resolveColumns(self.alloc, self.table.headers(), spec) catch return error.InvalidBig;
        defer self.alloc.free(cols);
        for (cols) |col| self.cols[col + self.synthetic].big = @max(self.cols[col + self.synthetic].big, level);
    }

    //
    // buildXXX
    //

    // Regular columns get up to 10 chars of floor. Big columns get up to 15 so
    // modest columns can become fully readable with -b.
    fn buildFloor(self: *AutoLayout) void {
        const fair_share = self.budget / self.cols.len;

        for (self.cols) |*col| {
            const max_width: usize = if (col.big != 0) 15 else 10;
            const bound = std.math.clamp(fair_share, 2, max_width);
            col.floor = @min(col.natural, bound);
            // If truncation would save only a few chars, show the whole value.
            if (col.natural >= 10 and col.floor + 4 >= col.natural) col.floor = col.natural;
        }
    }

    // Cap each column's autolayout range so one giant column cannot absorb the
    // entire width budget before narrower columns get useful space.
    fn buildCeil(self: *AutoLayout) void {
        // Let a wide column grow, but cap it at 5x fair share so it cannot
        // dominate the table.
        const ceil_bound = std.math.clamp(self.budget / self.cols.len, 2, 10) * 5;
        for (self.cols) |*col| {
            col.ceil = @min(col.natural, ceil_bound);
        }
    }

    // Plain -b only changes allocation basis. It must still fit termwidth.
    fn buildBasis(self: *AutoLayout) void {
        for (self.cols) |*col| {
            col.basis = if (col.big == 0) 1 else 2;
        }
    }

    //
    // Apply -bb/-bbb. Note that this happens after autolayout and can
    // intentionally overflow term
    //

    fn bigger(self: *AutoLayout, widths: []usize) !void {
        for (self.cols, 0..) |col, ii| {
            if (col.big >= 2) {
                const off = ii - self.synthetic;
                widths[ii] = @max(widths[ii], @min(try p90Width(self.alloc, self.table.column(off)), col.natural));
            }
            if (col.big >= 3) {
                widths[ii] = @max(widths[ii], col.natural);
            }
        }
    }

    // Water-fill between floor and ceil. Basis changes how quickly columns grow
    // inside that bounded range; ceil still protects the total fit.
    fn allocate(self: AutoLayout) ![]usize {
        const ncols = self.cols.len;

        // If budget is too small, give up and just use floor
        const floor_sum = AutoCol.sum(self.cols, .floor);
        const ceil_sum = AutoCol.sum(self.cols, .ceil);
        if (self.budget <= floor_sum or ceil_sum == floor_sum) {
            return try AutoCol.dupe(self.alloc, self.cols, .floor);
        }

        // diffs is each column's ceil-floor span, scaled by basis.
        var diffs = try self.alloc.alloc(usize, ncols);
        defer self.alloc.free(diffs);
        for (self.cols, 0..) |col, i| {
            diffs[i] = (col.ceil - col.floor) * col.basis;
        }
        const diffs_sum = util.sum(usize, diffs);

        // ratio maps remaining budget onto each weighted diff.
        const ratio = @as(f64, @floatFromInt(self.budget - floor_sum)) / @as(f64, @floatFromInt(diffs_sum));
        var nice = try self.alloc.alloc(usize, ncols);
        errdefer self.alloc.free(nice);
        for (self.cols, 0..) |col, i| {
            nice[i] = col.floor + @min(col.ceil - col.floor, @as(usize, @trunc(@as(f64, @floatFromInt(diffs[i])) * ratio)));
        }

        // due to @trunc, may have a few bit leftover
        const extra = self.budget -| util.sum(usize, nice);
        if (extra > 0) {
            try self.roundUpToBudget(nice, extra);
        }

        return nice;
    }

    // Handa extra budget to cols that need it the most
    fn roundUpToBudget(self: AutoLayout, nice: []usize, extra: usize) !void {
        const SpareWidth = struct { cols: []const AutoCol, result: []const usize };

        const indexes = try util.range(self.alloc, self.cols.len);
        defer self.alloc.free(indexes);
        const spare: SpareWidth = .{ .cols = self.cols, .result = nice };
        std.sort.block(usize, indexes, spare, struct {
            fn lessThan(ctx: SpareWidth, a: usize, b: usize) bool {
                return (ctx.cols[b].ceil - ctx.result[b]) < (ctx.cols[a].ceil - ctx.result[a]);
            }
        }.lessThan);

        var remaining = extra;
        for (indexes) |index| {
            if (remaining == 0) break;
            if (nice[index] < self.cols[index].ceil) {
                nice[index] += 1;
                remaining -= 1;
            }
        }
    }
};

//
// Per-col state during AutoLayout. A few simple helpers as well.
//

const AutoCol = struct {
    natural: usize,
    floor: usize = 0,
    ceil: usize = 0,
    basis: usize = 1,
    big: usize = 0,

    // Synthetic columns never get big behavior because users address only real
    // table headers.
    fn initAll(alloc: std.mem.Allocator, natural: []const usize) ![]AutoCol {
        const cols = try alloc.alloc(AutoCol, natural.len);
        for (natural, 0..) |nat, ii| {
            cols[ii] = .{
                .natural = nat,
            };
        }
        return cols;
    }

    const AutoColField = enum { natural, floor, ceil };

    fn sum(cols: []const AutoCol, comptime which: AutoColField) usize {
        var total: usize = 0;
        for (cols) |col| total += col.field(which);
        return total;
    }

    fn dupe(alloc: std.mem.Allocator, cols: []const AutoCol, comptime which: AutoColField) ![]usize {
        const out = try alloc.alloc(usize, cols.len);
        errdefer alloc.free(out);
        for (cols, 0..) |col, ii| out[ii] = col.field(which);
        return out;
    }

    fn field(self: AutoCol, comptime which: AutoColField) usize {
        return switch (which) {
            .natural => self.natural,
            .floor => self.floor,
            .ceil => self.ceil,
        };
    }
};

//
// helpers
//

fn p90Width(alloc: std.mem.Allocator, column: @import("column.zig").Column) !usize {
    const n = column.table.nrows();
    const widths = try alloc.alloc(usize, n);
    defer alloc.free(widths);
    for (0..n) |ii| widths[ii] = doomicode.displayWidth(column.field(ii));
    std.sort.block(usize, widths, {}, comptime std.sort.asc(usize));
    return @max(doomicode.displayWidth(column.name), util.percentile(usize, widths, 90));
}

fn measure(table: *const Table, rows: enum { headers, fields }) ![]usize {
    const alloc = table.app.alloc;
    var widths = std.ArrayList(usize).empty;
    errdefer widths.deinit(alloc);
    if (table.config.row_numbers) {
        try widths.append(alloc, util.digits(usize, table.nrows()));
    }
    for (table.columns) |column| {
        const width = switch (rows) {
            .headers => doomicode.displayWidth(column.name),
            .fields => column.width,
        };
        try widths.append(alloc, width);
    }

    const min_col_width = 2;
    for (widths.items, 0..) |_, i| {
        widths.items[i] = @max(widths.items[i], min_col_width);
    }

    return widths.toOwnedSlice(alloc);
}

//
// testing
//

test "layout cases" {
    const cases = [_]struct {
        config: types.Config,
        input: []const u8,
        want: []const usize,
    }{
        .{ .config = .{ .width = .{ .chars = 100 } }, .input = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa,bbbbbbbbbbbbbbbbbbbb,cccccccccc\nx,y,z\n", .want = &.{ 32, 20, 10 } },
        .{ .config = .{ .width = .{ .chars = 50 } }, .input = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa,bbbbbbbbbbbbbbbbbbbb,cccccccccc\nx,y,z\n", .want = &.{ 16, 12, 10 } },
        .{ .config = .{ .width = .{ .chars = 39 } }, .input = "1234567,123456789,12345678901\nx,y,z\n", .want = &.{ 7, 9, 11 } },
        .{ .config = .{ .width = .{ .chars = 100 } }, .input = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa,bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb,ccccccccccccc,dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd,eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\nx,x,x,x,x\n", .want = &.{ 15, 18, 13, 18, 18 } },
        .{ .config = .{ .width = .max }, .input = "1234567,123456789,12345678901\nx,y,z\n", .want = &.{ 7, 9, 11 } },
        .{ .config = .{ .width = .min }, .input = "alpha,beta,gamma\nx,y,z\n", .want = &.{ 5, 4, 5 } },
        .{ .config = .{ .width = .{ .chars = 80 } }, .input = "", .want = &.{} },
    };

    for (cases) |tc| try expectLayout(tc.config, tc.input, tc.want);
}

test "layout handles tiny terminals without underflow" {
    var tt = try test_support.initTable(testing.allocator, .{ .width = .{ .chars = 40 } }, "12345678,12345678,12345678,12345678,12345678,12345678,12345678,12345678\nx,x,x,x,x,x,x,x\n");
    defer tt.deinit();
    const table = tt.table;
    const l = try Layout.init(table);
    defer l.deinit(testing.allocator);
    try testing.expectEqual(@as(usize, 8), l.widths.len);
}

test "layout makes columns big monotonically" {
    const regular = try layoutTest(.{ .width = .{ .chars = 80 } }, bigFixture);
    defer testing.allocator.free(regular);
    const big = try layoutTest(.{ .width = .{ .chars = 80 }, .big1 = "wide" }, bigFixture);
    defer testing.allocator.free(big);
    const big2 = try layoutTest(.{ .width = .{ .chars = 80 }, .big2 = "wide" }, bigFixture);
    defer testing.allocator.free(big2);
    const big3 = try layoutTest(.{ .width = .{ .chars = 80 }, .big3 = "wide" }, bigFixture);
    defer testing.allocator.free(big3);

    try testing.expect(big[1] >= regular[1]);
    try testing.expect(big2[1] >= big[1]);
    try testing.expect(big3[1] >= big2[1]);
    try testing.expect(util.sum(usize, big) <= availableForTest(80, regular.len));
    try testing.expectEqual(@as(usize, 30), big3[1]);
}

test "layout -b stays fitted when basis allocation changes widths" {
    const regular = try layoutTest(.{ .width = .{ .chars = 80 } }, bigFitFixture);
    defer testing.allocator.free(regular);
    const big = try layoutTest(.{ .width = .{ .chars = 80 }, .big1 = "b" }, bigFitFixture);
    defer testing.allocator.free(big);

    const available = availableForTest(80, regular.len);
    try testing.expect(big[1] > regular[1]);
    try testing.expect(util.sum(usize, big) <= available);
}

test "layout -b allows modest columns to expand to 15 chars" {
    const regular = try layoutTest(.{ .width = .{ .chars = 50 } }, bigMinFixture);
    defer testing.allocator.free(regular);
    const big = try layoutTest(.{ .width = .{ .chars = 50 }, .big1 = "b" }, bigMinFixture);
    defer testing.allocator.free(big);

    const available = availableForTest(50, regular.len);
    try testing.expect(regular[1] < 15);
    try testing.expectEqual(@as(usize, 15), big[1]);
    try testing.expect(util.sum(usize, big) <= available);
}

test "layout big2 expands to p90 width" {
    const widths = try layoutTest(.{ .width = .{ .chars = 48 }, .big2 = "wide" }, bigFixture);
    defer testing.allocator.free(widths);

    try testing.expect(widths[1] >= 20);
    try testing.expect(widths[1] < 30);
}

test "layout big columns account for row numbers" {
    const regular = try layoutTest(.{ .width = .{ .chars = 80 }, .row_numbers = true }, bigFixture);
    defer testing.allocator.free(regular);
    const big = try layoutTest(.{ .width = .{ .chars = 80 }, .row_numbers = true, .big1 = "wide" }, bigFixture);
    defer testing.allocator.free(big);
    const big2 = try layoutTest(.{ .width = .{ .chars = 80 }, .row_numbers = true, .big2 = "wide" }, bigFixture);
    defer testing.allocator.free(big2);
    const big3 = try layoutTest(.{ .width = .{ .chars = 80 }, .row_numbers = true, .big3 = "wide" }, bigFixture);
    defer testing.allocator.free(big3);

    try testing.expect(big[2] >= regular[2]);
    try testing.expect(big2[2] >= big[2]);
    try testing.expect(big3[2] >= big2[2]);
    try testing.expectEqual(@as(usize, 30), big3[2]);
}

test "layout rejects big against hidden columns" {
    try testing.expectError(error.InvalidBig, layoutTest(.{ .select = "name", .big1 = "wide" }, bigFixture));
    try testing.expectError(error.InvalidBig, layoutTest(.{ .select = "name", .big2 = "wide" }, bigFixture));
    try testing.expectError(error.InvalidBig, layoutTest(.{ .select = "name", .big3 = "wide" }, bigFixture));
}

test "measure includes row numbers and unicode width" {
    var tt = try test_support.initTable(testing.allocator, .{ .row_numbers = true }, "a,\xc3\xa9\xc3\xa9\n10,x\n");
    defer tt.deinit();
    const table = tt.table;
    const widths = try measure(table, .fields);
    defer testing.allocator.free(widths);

    try testing.expectEqualSlices(usize, &[_]usize{ 2, 2, 2 }, widths);
}

test "measure true uses header labels" {
    var tt = try test_support.initTable(testing.allocator, .{}, "alpha,b\nx,longlonglong\n");
    defer tt.deinit();
    const table = tt.table;
    const widths = try measure(table, .headers);
    defer testing.allocator.free(widths);

    try testing.expectEqualSlices(usize, &[_]usize{ 5, 2 }, widths);
}

test "measure returns empty layout for empty inputs" {
    try expectMeasure(.{}, "", &.{});
    try expectMeasure(.{}, "a,b\n", &.{});
}

test "measure ignores empty data field width" {
    var tt = try test_support.initTable(testing.allocator, .{}, "alpha,beta\n,xyz\n");
    defer tt.deinit();
    const table = tt.table;
    const widths = try measure(table, .fields);
    defer testing.allocator.free(widths);

    try testing.expectEqualSlices(usize, &[_]usize{ 5, 4 }, widths);
}

fn expectLayout(config: types.Config, input: []const u8, want: []const usize) !void {
    var tt = try test_support.initTable(testing.allocator, config, input);
    defer tt.deinit();
    const table = tt.table;
    const got = try Layout.init(table);
    defer got.deinit(testing.allocator);
    try testing.expectEqualSlices(usize, want, got.widths);
}

fn expectMeasure(config: types.Config, input: []const u8, want: []const usize) !void {
    var tt = try test_support.initTable(testing.allocator, config, input);
    defer tt.deinit();
    const table = tt.table;
    const got = try measure(table, .fields);
    defer testing.allocator.free(got);
    try testing.expectEqualSlices(usize, want, got);
}

fn availableForTest(term_width: usize, ncols: usize) usize {
    return term_width -| (ncols * 3 + 1 + width_fudge);
}

// Return caller-owned widths after tearing down the temporary test table.
fn layoutTest(config: types.Config, input: []const u8) ![]usize {
    var tt = try test_support.initTable(testing.allocator, config, input);
    defer tt.deinit();
    const got = try Layout.init(tt.table);
    defer got.deinit(testing.allocator);
    return try testing.allocator.dupe(usize, got.widths);
}

const bigFixture =
    \\name,wide,tiny
    \\a,xxxxxxxxxx,z
    \\b,xxxxxxxxxx,z
    \\c,xxxxxxxxxx,z
    \\d,xxxxxxxxxx,z
    \\e,xxxxxxxxxx,z
    \\f,xxxxxxxxxx,z
    \\g,xxxxxxxxxx,z
    \\h,xxxxxxxxxx,z
    \\i,xxxxxxxxxxxxxxxxxxxx,z
    \\j,xxxxxxxxxxxxxxxxxxxxxxxxxxxxxx,z
    \\
;

const bigFitFixture =
    \\a,b,c
    \\aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa,bbbbbbbbbbbbbbbbbbbbbbbbbbbbbb,cccccccccccccccccccccccccccccc
    \\
;

const bigMinFixture =
    \\a,b,c
    \\aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa,bbbbbbbbbbbbbbb,cccccccccccccccccccccccccccccc
    \\
;

const doomicode = @import("doomicode.zig");
const std = @import("std");
const Table = @import("table.zig").Table;
const testing = std.testing;
const test_support = @import("test_support.zig");
const types = @import("types.zig");
const util = @import("util.zig");
