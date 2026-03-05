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
    const tty = devtty.handle;

    // check TERM
    const term_opt = std.posix.getenv("TERM");
    util.tdebug("TERM={s}", .{term_opt orelse "<unset>"});
    const term = term_opt orelse return error.NotSupported;
    if (std.mem.startsWith(u8, term, "screen") or std.mem.startsWith(u8, term, "tmux") or std.mem.startsWith(u8, term, "dumb")) {
        util.tdebug("bad TERM, bailing", .{});
        return error.NotSupported;
    }

    // put tty into raw mode, but restore afterward
    var tio = try std.posix.tcgetattr(tty);
    const saved = tio;
    tio.lflag.ECHO = false;
    tio.lflag.ICANON = false;

    // set VMIN/VTIME
    var vmin: u8 = undefined;
    var vtime: u8 = undefined;
    if (builtin.os.tag == .linux) {
        vmin = @intFromEnum(std.os.linux.V.MIN);
        vtime = @intFromEnum(std.os.linux.V.TIME);
    } else if (builtin.os.tag == .macos) {
        // i suck at zig
        vmin = 16;
        vtime = 17;
    } else {
        return error.NotSupported;
    }

    // reads from dev/tty should have a 0.1s timeout
    const timeout_in_deciseconds: u8 = 1;
    tio.cc[vmin] = 0;
    tio.cc[vtime] = timeout_in_deciseconds;

    try std.posix.tcsetattr(tty, .NOW, tio);
    defer std.posix.tcsetattr(tty, .NOW, saved) catch {};
    util.tdebug("now in raw mode", .{});

    // OSC 11 asks for the background color. CSI 6n is a reliable fallback
    // response so we can detect terminals that ignore OSC 11.
    util.tdebug("OSC11", .{});
    try devtty.writeAll(ansi.esc ++ "]11;?\x07" ++ ansi.esc ++ "[6n");

    // first response, which is hopefully the OSC11 response
    const response1 = try readResponse(alloc, tty);
    defer alloc.free(response1);
    const inspect1 = try util.inspect(alloc, response1);
    defer alloc.free(inspect1);
    util.tdebug("response1={s}", .{inspect1});
    if (response1.len < 2 or response1[1] != ']') {
        util.tdebug("terminal ignored osc11", .{});
        return error.NotSupported;
    }

    // second response (we ignore this)
    const response2 = readResponse(alloc, tty) catch null;
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

//
// read a response, defensively
//

fn readResponse(alloc: std.mem.Allocator, fd: std.posix.fd_t) ![]u8 {
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

const ansi = @import("ansi.zig");
const builtin = @import("builtin");
const Color = @import("color.zig").Color;
const std = @import("std");
const util = @import("util.zig");
