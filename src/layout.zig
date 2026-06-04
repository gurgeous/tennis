//
// Glossary:
//   natural    Measured full width of a column, including header and fields.
//   budget     Data-field width available after borders and slack.
//   narrow     "Narrow" columns get to keep natural width.
//   wide       "Wide "columns split the leftover budget after narrow.
//

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

        // the main event!
        var auto = try AutoLayout.init(table);
        defer auto.deinit();
        return .{ .widths = try auto.autolayout() };
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

const fudge = 2;

const AutoLayout = struct {
    alloc: std.mem.Allocator,
    cols: []LayoutCol = &.{},
    table: *Table,

    fn init(table: *Table) !AutoLayout {
        const alloc = table.app.alloc;

        // calculate synthetic/ncols
        var synthetic: usize = 0;
        if (table.config.row_numbers) synthetic += 1;
        const ncols = synthetic + table.ncols();

        // calc natural (full) width of each col
        const natural = try measure(table, .fields);
        defer alloc.free(natural);

        // which cols are big?
        var bigs: [3][]usize = undefined;
        const specs = [_][]const u8{ table.config.big1, table.config.big2, table.config.big3 };
        for (specs, 0..) |spec, ii| {
            bigs[ii] = types.resolveColumns(alloc, table.headers(), spec) catch return error.InvalidBig;
        }
        defer for (bigs) |cols| alloc.free(cols);

        var self: AutoLayout = .{ .alloc = alloc, .table = table, .cols = try alloc.alloc(LayoutCol, ncols) };
        errdefer self.deinit();

        // populate cols
        for (0..ncols) |ii| {
            const src = if (ii >= synthetic) ii - synthetic else null;
            const big = bigLevel(src, &bigs);
            self.cols[ii] = .{ .big = big, .ii = ii, .natural = natural[ii], .src = src };
        }

        // sort cols by natural width
        std.sort.block(LayoutCol, self.cols, {}, struct {
            fn lessThan(_: void, a: LayoutCol, b: LayoutCol) bool {
                if (a.natural == b.natural) return a.ii < b.ii;
                return a.natural < b.natural;
            }
        }.lessThan);

        return self;
    }

    fn deinit(self: *AutoLayout) void {
        self.alloc.free(self.cols);
    }

    fn autolayout(self: *AutoLayout) ![]usize {
        // how much space do we have? only goes down as we proceed here
        var budget = self.table.termWidth() -| (calcChromeWidth(self.cols.len) + fudge);

        // 1. Big1: -b columns reserve half the budget.
        const parts = util.partition(LayoutCol, self.cols, struct {
            fn pred(col: LayoutCol) bool {
                return col.big == 1;
            }
        }.pred);
        const big1 = self.cols[0..parts];
        const work = self.cols[parts..];
        if (big1.len > 0) {
            budget = self.reserveBig1(big1, budget);
        }

        // 2. Narrow: "narrow" columns get natural width
        const mark = narrow(work, &budget);

        // 3. Wide: leftover "wide" columns split leftover budget.
        if (mark < work.len) {
            wide(work[mark..], budget);
        }

        // 4. Big23: Overflow for -b and -bb
        try self.big23();

        // done!
        const nice = try self.alloc.alloc(usize, self.cols.len);
        errdefer self.alloc.free(nice);
        for (self.cols) |col| {
            nice[col.ii] = col.nice;
        }
        return nice;
    }

    // 1. Big1: -b cols get half our budget.
    fn reserveBig1(_: *AutoLayout, cols: []LayoutCol, budget_in: usize) usize {
        var budget = budget_in;
        const per = (budget_in / 2) / cols.len;
        for (cols) |*col| {
            col.nice = @min(col.natural, per);
            budget -|= col.nice;
        }
        return budget;
    }

    // 2. Narrow phase: "narrow" columns get natural width while they fit into
    // fair share. Each accepted column lowers the budget, but also lowers the
    // number of columns competing for that budget. Stop when the current column
    // is wider than its fair share. `mark` tracks where we stopped.
    fn narrow(cols: []LayoutCol, budget: *usize) usize {
        for (0..cols.len) |ii| {
            // what's the "fair" share for remaining cols from here on out?
            const ncols = cols.len - ii;
            const fair_share = budget.* / ncols;

            // is this column "narrow" enough to fit into fair_share? If not, bail
            var cur = &cols[ii];
            if (cur.natural > fair_share) return ii;

            // narrow column gets to be full width
            cur.nice = cur.natural;
            budget.* -|= cur.nice;
        }
        return cols.len;
    }

    // 3. Wide phase: leftover "wide" columns split leftover budget. how
    // much space do we have to fill? this only goes down..
    fn wide(cols: []LayoutCol, budget_in: usize) void {
        const fair_share = budget_in / cols.len;
        var budget = budget_in % cols.len;
        for (cols) |*cur| {
            cur.nice = fair_share;
            if (budget > 0) {
                cur.nice += 1;
                budget -= 1;
            }
        }
    }

    // 4. Adjust layout for -b and -bb
    fn big23(self: *AutoLayout) !void {
        for (self.cols) |*cur| {
            const src = cur.src orelse continue;
            if (cur.big == 2) {
                cur.nice = @max(cur.nice, try self.table.column(src).p90(self.alloc));
            }
            if (cur.big == 3) {
                cur.nice = @max(cur.nice, cur.natural);
            }
        }
    }
};

//
// Per-col state for AutoLayout.
//

const LayoutCol = struct {
    big: usize = 0, // -b -bb -bbb level for this col, if any
    ii: usize, // display order (row_numbers will be 0, for example)
    natural: usize, // "natural" width (max width across all fields)
    nice: usize = 0, // final width
    src: ?usize, // which data column does this belong to? (row_numbers will be null)
};

//
// standalone helpers
//

// -b -bb -bbb level for src, if any
fn bigLevel(src: ?usize, bigs: []const []const usize) usize {
    const col = src orelse return 0;
    var level = bigs.len;
    while (level > 0) : (level -= 1) {
        const present = std.mem.indexOfScalar(usize, bigs[level - 1], col) != null;
        if (present) return level;
    }
    return 0;
}

// measure natural field/header widths for all cols
fn measure(table: *const Table, rows: enum { headers, fields }) ![]usize {
    const alloc = table.app.alloc;

    var widths = std.ArrayList(usize).empty;
    errdefer widths.deinit(alloc);

    // synthetic cols
    if (table.config.row_numbers) {
        try widths.append(alloc, util.digits(usize, table.nrows()));
    }

    // other cols, calculate max width
    for (table.columns) |column| {
        const width = switch (rows) {
            .headers => doomicode.displayWidth(column.name),
            .fields => column.width,
        };
        try widths.append(alloc, width);
    }

    // min 2
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
        .{ .config = .{ .width = .{ .chars = 50 } }, .input = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa,bbbbbbbbbbbbbbbbbbbb,cccccccccc\nx,y,z\n", .want = &.{ 14, 14, 10 } },
        .{ .config = .{ .width = .{ .chars = 39 } }, .input = "1234567,123456789,12345678901\nx,y,z\n", .want = &.{ 7, 9, 11 } },
        .{ .config = .{ .width = .{ .chars = 100 } }, .input = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa,bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb,ccccccccccccc,dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd,eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\nx,x,x,x,x\n", .want = &.{ 18, 17, 13, 17, 17 } },
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
    return term_width -| (ncols * 3 + 1 + fudge);
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
const test_support = @import("test_support.zig");
const testing = std.testing;
const types = @import("types.zig");
const util = @import("util.zig");
