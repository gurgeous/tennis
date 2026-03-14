// Query the terminal's default background color.
//
// This is best-effort. We ask xterm-compatible terminals for OSC 11 (background
// color), then immediately send CSI 6n as a fallback marker. If the first
// response we read is cursor position instead of OSC, we assume OSC 11 was
// ignored and return an error.

pub fn isDark(alloc: std.mem.Allocator) !bool {
    // open dev/tty
    var devtty = std.fs.openFileAbsolute("/dev/tty", .{ .mode = .read_write }) catch |err| {
        util.tdebug("could not open /dev/tty: {s}", .{@errorName(err)});
        return error.NotSupported;
    };
    defer devtty.close();
    return try isDarkWith(alloc, std.posix.getenv("TERM"), builtin.os.tag, RealTty{ .file = &devtty });
}

fn isDarkWith(alloc: std.mem.Allocator, term_opt: ?[]const u8, os_tag: std.Target.Os.Tag, tty: anytype) !bool {
    util.tdebug("TERM={s}", .{term_opt orelse "<unset>"});
    _ = try supportedTerm(term_opt);

    var tio = try tty.tcgetattr();
    const saved = tio;
    tio.lflag.ECHO = false;
    tio.lflag.ICANON = false;

    const cc = try timeoutIndexes(os_tag);
    const timeout_in_deciseconds: u8 = 1;
    tio.cc[cc.vmin] = 0;
    tio.cc[cc.vtime] = timeout_in_deciseconds;

    try tty.tcsetattr(tio);
    defer tty.tcsetattr(saved) catch {};
    util.tdebug("now in raw mode", .{});

    util.tdebug("OSC11", .{});
    try tty.writeAll(ansi.esc ++ "]11;?\x07" ++ ansi.esc ++ "[6n");

    const response1 = try tty.readResponse(alloc);
    defer alloc.free(response1);
    const inspect1 = try util.inspect(alloc, response1);
    defer alloc.free(inspect1);
    util.tdebug("response1={s}", .{inspect1});
    if (!isOsc11Response(response1)) {
        util.tdebug("terminal ignored osc11", .{});
        return error.NotSupported;
    }

    const response2 = tty.readResponse(alloc) catch null;
    defer if (response2) |buf| alloc.free(buf);
    if (response2) |buf| {
        const inspect2 = try util.inspect(alloc, buf);
        defer alloc.free(inspect2);
        util.tdebug("response2={s}", .{inspect2});
    }

    const color = try parseResponse(response1);
    const hex = try color.toHex(alloc);
    defer alloc.free(hex);
    util.tdebug("detected {s} => {s}", .{ hex, if (color.isDark()) "dark" else "light" });
    return color.isDark();
}

fn supportedTerm(term_opt: ?[]const u8) ![]const u8 {
    const term = term_opt orelse return error.NotSupported;
    if (std.mem.startsWith(u8, term, "screen") or std.mem.startsWith(u8, term, "tmux") or std.mem.startsWith(u8, term, "dumb")) {
        util.tdebug("bad TERM, bailing", .{});
        return error.NotSupported;
    }
    return term;
}

// Return the cc indexes used to control non-blocking tty reads.
fn timeoutIndexes(os_tag: std.Target.Os.Tag) !struct { vmin: u8, vtime: u8 } {
    return switch (os_tag) {
        .linux => .{
            .vmin = @intFromEnum(std.os.linux.V.MIN),
            .vtime = @intFromEnum(std.os.linux.V.TIME),
        },
        .macos => .{
            // Darwin exposes these slots as constants in system headers, not Zig std.
            .vmin = 16,
            .vtime = 17,
        },
        else => error.NotSupported,
    };
}

fn isOsc11Response(response: []const u8) bool {
    return response.len >= 2 and response[1] == ']';
}

const RealTty = struct {
    file: *std.fs.File,

    fn tcgetattr(self: @This()) !std.posix.termios {
        return try std.posix.tcgetattr(self.file.handle);
    }

    fn tcsetattr(self: @This(), tio: std.posix.termios) !void {
        try std.posix.tcsetattr(self.file.handle, .NOW, tio);
    }

    fn writeAll(self: @This(), bytes: []const u8) !void {
        try self.file.writeAll(bytes);
    }

    fn readResponse(self: @This(), alloc: std.mem.Allocator) ![]u8 {
        return try termReadResponse(alloc, self.file.handle);
    }
};

//
// read a response, defensively
//

fn termReadResponse(alloc: std.mem.Allocator, fd: std.posix.fd_t) ![]u8 {
    // fast forward to ESC
    while (try util.readByte(fd) != ansi.esc[0]) {}

    // next char should be either [ or ]
    const rtype = try util.readByte(fd);
    if (!(rtype == '[' or rtype == ']')) return error.InvalidData;

    // append first two bytes
    var out = try std.ArrayList(u8).initCapacity(alloc, 32);
    errdefer out.deinit(alloc);
    try out.append(alloc, ansi.esc[0]);
    try out.append(alloc, rtype);

    // now read the response
    while (true) {
        const ch = try util.readByte(fd);
        try out.append(alloc, ch);
        if (rtype == '[' and ch == 'R') break;
        if (rtype == ']' and ch == ansi.bel[0]) break;
        if (rtype == ']' and std.mem.endsWith(u8, out.items, ansi.st)) break;
    }

    return out.toOwnedSlice(alloc);
}

fn parseResponse(s: []const u8) !Color {
    // ESC ]11;rgb:0b0b/2727/3232 BEL
    const prefix = ansi.esc ++ "]11;rgb:";
    if (!std.mem.startsWith(u8, s, prefix)) return error.InvalidData;

    // remove slashes
    var hex: [16]u8 = undefined;
    const slashed = if (std.mem.endsWith(u8, s, ansi.bel))
        s[prefix.len .. s.len - ansi.bel.len]
    else if (std.mem.endsWith(u8, s, ansi.st))
        s[prefix.len .. s.len - ansi.st.len]
    else
        return error.InvalidData;
    const n = std.mem.replacementSize(u8, slashed, "/", "");
    _ = std.mem.replace(u8, slashed, "/", "", &hex);

    // important to use the correct slice w/n here
    return try Color.initHex(hex[0..n]);
}

//
// tests
//

test "parse osc11 response" {
    try std.testing.expect((try parseResponse("\x1b]11;rgb:0000/0000/0000\x1b\\")).isDark());
    try std.testing.expect((try parseResponse("\x1b]11;rgb:ffff/ffff/ffff\x1b\\")).isLight());
}

test "parse osc11 response accepts bel terminator" {
    try std.testing.expect((try parseResponse("\x1b]11;rgb:ffff/ffff/ffff\x07")).isLight());
}

test "parse osc11 response rejects invalid prefix" {
    try std.testing.expectError(error.InvalidData, parseResponse("\x1b]10;rgb:ffff/ffff/ffff\x07"));
}

test "parse osc11 response rejects malformed payload" {
    try std.testing.expectError(error.InvalidCharacter, parseResponse("\x1b]11;rgb:zzzz/ffff/ffff\x07"));
}

test "supportedTerm validates TERM" {
    try std.testing.expectEqualStrings("xterm-256color", try supportedTerm("xterm-256color"));
    try std.testing.expectError(error.NotSupported, supportedTerm(null));
    try std.testing.expectError(error.NotSupported, supportedTerm("screen-256color"));
    try std.testing.expectError(error.NotSupported, supportedTerm("tmux-256color"));
    try std.testing.expectError(error.NotSupported, supportedTerm("dumb"));
}

test "timeoutIndexes supports linux and macos" {
    const linux = try timeoutIndexes(.linux);
    try std.testing.expectEqual(@as(u8, @intFromEnum(std.os.linux.V.MIN)), linux.vmin);
    try std.testing.expectEqual(@as(u8, @intFromEnum(std.os.linux.V.TIME)), linux.vtime);

    const macos = try timeoutIndexes(.macos);
    try std.testing.expectEqual(@as(u8, 16), macos.vmin);
    try std.testing.expectEqual(@as(u8, 17), macos.vtime);

    try std.testing.expectError(error.NotSupported, timeoutIndexes(.windows));
}

test "isOsc11Response distinguishes osc and csi" {
    try std.testing.expect(isOsc11Response("\x1b]11;rgb:ffff/ffff/ffff\x07"));
    try std.testing.expect(!isOsc11Response(""));
    try std.testing.expect(!isOsc11Response("\x1b[1;1R"));
}

test "isDarkWith returns parsed darkness and restores tty state" {
    const FakeTty = struct {
        tio: std.posix.termios = std.mem.zeroes(std.posix.termios),
        configured: std.posix.termios = std.mem.zeroes(std.posix.termios),
        set_count: usize = 0,
        write_buf: [32]u8 = undefined,
        write_len: usize = 0,
        first: []const u8,
        second: ?[]const u8 = null,
        reads: usize = 0,

        fn tcgetattr(self: *@This()) !std.posix.termios {
            return self.tio;
        }

        fn tcsetattr(self: *@This(), tio: std.posix.termios) !void {
            if (self.set_count == 0) self.configured = tio;
            self.tio = tio;
            self.set_count += 1;
        }

        fn writeAll(self: *@This(), bytes: []const u8) !void {
            @memcpy(self.write_buf[0..bytes.len], bytes);
            self.write_len = bytes.len;
        }

        fn readResponse(self: *@This(), alloc: std.mem.Allocator) ![]u8 {
            defer self.reads += 1;
            return switch (self.reads) {
                0 => try alloc.dupe(u8, self.first),
                1 => if (self.second) |response| try alloc.dupe(u8, response) else error.WouldBlock,
                else => error.WouldBlock,
            };
        }
    };

    var tty = FakeTty{
        .first = "\x1b]11;rgb:0000/0000/0000\x07",
        .second = "\x1b[1;1R",
    };
    try std.testing.expect(try isDarkWith(std.testing.allocator, "xterm-256color", .linux, &tty));
    try std.testing.expectEqualStrings(ansi.esc ++ "]11;?\x07" ++ ansi.esc ++ "[6n", tty.write_buf[0..tty.write_len]);
    try std.testing.expectEqual(@as(usize, 2), tty.set_count);
    try std.testing.expectEqual(@as(u8, 1), tty.configured.cc[@intFromEnum(std.os.linux.V.TIME)]);
}

test "isDarkWith returns not supported when osc11 is ignored" {
    const FakeTty = struct {
        fn tcgetattr(_: *@This()) !std.posix.termios {
            return std.mem.zeroes(std.posix.termios);
        }

        fn tcsetattr(_: *@This(), _: std.posix.termios) !void {}

        fn writeAll(_: *@This(), _: []const u8) !void {}

        fn readResponse(_: *@This(), alloc: std.mem.Allocator) ![]u8 {
            return try alloc.dupe(u8, "\x1b[1;1R");
        }
    };

    var tty = FakeTty{};
    try std.testing.expectError(error.NotSupported, isDarkWith(std.testing.allocator, "xterm-256color", .linux, &tty));
}

test "readResponse reads csi response" {
    const fds = try std.posix.pipe();
    defer std.posix.close(fds[0]);
    defer std.posix.close(fds[1]);

    _ = try std.posix.write(fds[1], "junk\x1b[12;34R");
    const out = try termReadResponse(std.testing.allocator, fds[0]);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("\x1b[12;34R", out);
}

test "readResponse reads osc bel response" {
    const fds = try std.posix.pipe();
    defer std.posix.close(fds[0]);
    defer std.posix.close(fds[1]);

    _ = try std.posix.write(fds[1], "\x1b]11;rgb:ffff/ffff/ffff\x07");
    const out = try termReadResponse(std.testing.allocator, fds[0]);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("\x1b]11;rgb:ffff/ffff/ffff\x07", out);
}

test "readResponse rejects invalid response type" {
    const fds = try std.posix.pipe();
    defer std.posix.close(fds[0]);
    defer std.posix.close(fds[1]);

    _ = try std.posix.write(fds[1], "\x1bXoops");
    try std.testing.expectError(error.InvalidData, termReadResponse(std.testing.allocator, fds[0]));
}

const ansi = @import("ansi.zig");
const builtin = @import("builtin");
const Color = @import("color.zig").Color;
const std = @import("std");
const util = @import("util.zig");
