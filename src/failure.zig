// Centralized app failures plus user-facing error formatting.

// One structured failure plus any optional attached detail/header data.
pub const Failure = struct {
    code: FailureCode,
    detail: ?[]const u8 = null,

    // Convert one plain error code into a structured app failure when possible.
    pub fn fromError(err: anyerror) ?Failure {
        return switch (err) {
            error.CouldNotReadStdin => .{ .code = .could_not_read_stdin },
            error.InvalidDigits => .{ .code = .invalid_digits },
            error.InvalidHeadTail => .{ .code = .invalid_head_tail },
            error.InvalidHeadValue => .{ .code = .invalid_head_value },
            error.InvalidTailValue => .{ .code = .invalid_tail_value },
            error.JaggedCsv => .{ .code = .jagged_csv },
            error.SqliteCliFailed => .{ .code = .sqlite_cli_failed },
            error.SqliteCliMissing => .{ .code = .sqlite_cli_missing },
            error.SqliteTooLarge => .{ .code = .sqlite_too_large },
            error.SqliteNoTables => .{ .code = .sqlite_no_tables },
            error.SqliteRequiresFile => .{ .code = .sqlite_requires_file },
            error.SyntaxError => .{ .code = .invalid_json },
            error.TooManyArguments => .{ .code = .too_many_arguments },
            error.UnexpectedEndOfFile => .{ .code = .invalid_csv },
            error.UnexpectedEndOfInput => .{ .code = .invalid_json },
            error.Windows => .{ .code = .windows },
            // Some errors need extra context or should still propagate normally.
            else => null,
        };
    }

    // Clap error => failure.
    pub fn fromClapError(alloc: std.mem.Allocator, err: anyerror, diag: *clap.Diagnostic) !Failure {
        if (Failure.fromError(err)) |fatal| return fatal;
        return .{ .code = .clap, .detail = try formatClap(alloc, err, diag) };
    }

    // FileNotFound => failure.
    pub fn fromFileNotFound(alloc: std.mem.Allocator, filename: []const u8) !Failure {
        return .{
            .code = .file_not_found,
            .detail = try std.fmt.allocPrint(alloc, "Could not read file '{s}'", .{filename}),
        };
    }

    // Table error => failure.
    pub fn fromTableError(alloc: std.mem.Allocator, err: anyerror, headers: []const []const u8) !Failure {
        return switch (err) {
            error.InvalidSelect => .{ .code = .invalid_select, .detail = try formatColumns(alloc, "--select", headers) },
            error.InvalidDeselect => .{ .code = .invalid_deselect, .detail = try formatColumns(alloc, "--deselect", headers) },
            error.InvalidSort => .{ .code = .invalid_sort, .detail = try formatColumns(alloc, "--sort", headers) },
            else => unreachable,
        };
    }

    // Release any owned detail attached to this failure.
    pub fn deinit(self: Failure, alloc: std.mem.Allocator) void {
        if (self.detail) |str| alloc.free(str);
    }

    // Render one failure with the standard banner/footer behavior.
    pub fn print(self: Failure) !void {
        try printBanner(util.stderr, self);
    }

    // Write one failure to the provided writer.
    pub fn write(self: Failure, writer: *std.Io.Writer) !void {
        switch (self.code) {
            .benchmark_requires_release => try writer.writeAll("BENCHMARK=1 requires `just benchmark` or a release build"),
            .could_not_read_stdin => try writer.writeAll("Could not read from stdin"),
            .invalid_csv => try writer.writeAll("That CSV file doesn't look right"),
            .invalid_digits => try writer.writeAll("Digits must be between 1 and 6"),
            .invalid_head_tail => try writer.writeAll("Use --head or --tail, not both"),
            .invalid_head_value => try writer.writeAll("Head must be greater than 0"),
            .invalid_json => try writer.writeAll("That JSON/JSONL file doesn't look right"),
            .invalid_tail_value => try writer.writeAll("Tail must be greater than 0"),
            .jagged_csv => try writer.writeAll("All csv rows must have same number of columns"),
            .sqlite_cli_failed => try writer.writeAll("Could not read that SQLite file with sqlite3"),
            .sqlite_cli_missing => try writer.writeAll("sqlite3 is required to read SQLite files"),
            .sqlite_no_tables => try writer.writeAll("That SQLite file has no ordinary tables"),
            .sqlite_requires_file => try writer.writeAll("SQLite input requires a file path"),
            .sqlite_too_large => try writer.writeAll("That SQLite table is too large to display"),
            .too_many_arguments => try writer.writeAll("Too many file arguments"),
            .windows => try writer.writeAll("Windows is not yet supported"),

            // these have details
            .clap, .file_not_found, .invalid_deselect, .invalid_select, .invalid_sort => try writer.writeAll(self.detail orelse unreachable),
        }
    }
};

// All user-visible failure codes for the CLI.
pub const FailureCode = enum {
    benchmark_requires_release,
    clap,
    could_not_read_stdin,
    file_not_found,
    invalid_csv,
    invalid_deselect,
    invalid_digits,
    invalid_head_tail,
    invalid_head_value,
    invalid_json,
    invalid_select,
    invalid_sort,
    invalid_tail_value,
    jagged_csv,
    sqlite_cli_failed,
    sqlite_cli_missing,
    sqlite_no_tables,
    sqlite_requires_file,
    sqlite_too_large,
    too_many_arguments,
    windows,
};

// Print the shared startup banner to the requested output stream.
pub fn printBanner(writer: *std.Io.Writer, fatal: ?Failure) !void {
    if (fatal) |value| {
        try writer.writeAll("tennis: ");
        try value.write(writer);
        try writer.writeByte('\n');
    }
    try writer.writeAll("tennis: try 'tennis --help' for more information\n");
}

// Render clap's diagnostic output into one owned string.
fn formatClap(alloc: std.mem.Allocator, err: anyerror, diag: *clap.Diagnostic) ![]u8 {
    var buf: [512]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    diag.report(&writer, err) catch {};

    const msg = util.strip(u8, writer.buffered());
    if (msg.len > 0) return alloc.dupe(u8, msg);
    return std.fmt.allocPrint(alloc, "Error while parsing arguments: {s}", .{@errorName(err)});
}

// Render one invalid column-spec error into an owned string.
fn formatColumns(alloc: std.mem.Allocator, flag: []const u8, row: []const []const u8) ![]u8 {
    var out = std.Io.Writer.Allocating.init(alloc);
    errdefer out.deinit();
    try out.writer.print("{s} didn't look right, should be a comma-separated list of columns.\n", .{flag});
    try out.writer.writeAll("tennis: column names: ");
    for (row, 0..) |header, ii| {
        if (ii > 0) try out.writer.writeAll(", ");
        try out.writer.writeAll(header);
    }
    return out.toOwnedSlice();
}

//
// testing
//

// Convert one failure into an owned string for tests and snapshots.
pub fn string(alloc: std.mem.Allocator, fatal: Failure) ![]u8 {
    var out = std.Io.Writer.Allocating.init(alloc);
    errdefer out.deinit();
    try fatal.write(&out.writer);
    return out.toOwnedSlice();
}

test "fromError covers direct mapped cases" {
    const cases = [_]struct {
        err: anyerror,
        want: FailureCode,
    }{
        .{ .err = error.InvalidDigits, .want = .invalid_digits },
        .{ .err = error.CouldNotReadStdin, .want = .could_not_read_stdin },
        .{ .err = error.SyntaxError, .want = .invalid_json },
        .{ .err = error.UnexpectedEndOfInput, .want = .invalid_json },
        .{ .err = error.Windows, .want = .windows },
        .{ .err = error.JaggedCsv, .want = .jagged_csv },
        .{ .err = error.SqliteCliFailed, .want = .sqlite_cli_failed },
        .{ .err = error.SqliteCliMissing, .want = .sqlite_cli_missing },
        .{ .err = error.SqliteNoTables, .want = .sqlite_no_tables },
        .{ .err = error.SqliteRequiresFile, .want = .sqlite_requires_file },
        .{ .err = error.SqliteTooLarge, .want = .sqlite_too_large },
    };

    for (cases) |tc| {
        const fatal = Failure.fromError(tc.err).?;
        try testing.expectEqual(tc.want, fatal.code);
    }
}

test "fromError returns null for unmapped errors" {
    try testing.expectEqual(@as(?Failure, null), Failure.fromError(error.OutOfMemory));
}

test "printBanner prints banner with and without failure" {
    var empty_buf: [128]u8 = undefined;
    var empty_writer = std.Io.Writer.fixed(&empty_buf);
    try printBanner(&empty_writer, null);
    try testing.expectEqualStrings("tennis: try 'tennis --help' for more information\n", empty_writer.buffered());

    var fatal_buf: [256]u8 = undefined;
    var fatal_writer = std.Io.Writer.fixed(&fatal_buf);
    try printBanner(&fatal_writer, .{ .code = .invalid_json });
    try testing.expect(std.mem.indexOf(u8, fatal_writer.buffered(), "tennis: That JSON/JSONL file doesn't look right\n") != null);
    try testing.expect(std.mem.indexOf(u8, fatal_writer.buffered(), "tennis: try 'tennis --help' for more information\n") != null);
}

test "write includes column headers" {
    const sort_failure = try Failure.fromTableError(testing.allocator, error.InvalidSort, &.{ "name", "score" });
    defer sort_failure.deinit(testing.allocator);
    const sort_msg = try string(testing.allocator, sort_failure);
    defer testing.allocator.free(sort_msg);
    try testing.expect(std.mem.indexOf(u8, sort_msg, "--sort") != null);
    try testing.expect(std.mem.indexOf(u8, sort_msg, "name, score") != null);

    const select_failure = try Failure.fromTableError(testing.allocator, error.InvalidSelect, &.{ "name", "score" });
    defer select_failure.deinit(testing.allocator);
    const select_msg = try string(testing.allocator, select_failure);
    defer testing.allocator.free(select_msg);
    try testing.expect(std.mem.indexOf(u8, select_msg, "--select") != null);
    try testing.expect(std.mem.indexOf(u8, select_msg, "name, score") != null);

    const deselect_failure = try Failure.fromTableError(testing.allocator, error.InvalidDeselect, &.{ "name", "score" });
    defer deselect_failure.deinit(testing.allocator);
    const deselect_msg = try string(testing.allocator, deselect_failure);
    defer testing.allocator.free(deselect_msg);
    try testing.expect(std.mem.indexOf(u8, deselect_msg, "--deselect") != null);
    try testing.expect(std.mem.indexOf(u8, deselect_msg, "name, score") != null);
}

const clap = @import("clap");
const std = @import("std");
const testing = std.testing;
const util = @import("util.zig");
