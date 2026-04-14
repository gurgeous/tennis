const std = @import("std");
const io = std.io;
const unicode = std.unicode;
const windows = std.os.windows;
const winapiGlue = @import("winapiGlue.zig");

pub const Modifiers = packed struct {
    shift: bool = false,
    alt: bool = false,
    ctrl: bool = false,
};

pub const KeyCode = union(enum) {
    char: u21,
    enter,
    esc,
    backspace,
    tab,
    up,
    down,
    left,
    right,
    home,
    end,
    page_up,
    page_down,
    insert,
    delete,
    f1,
    f2,
    f3,
    f4,
    f5,
    f6,
    f7,
    f8,
    f9,
    f10,
    f11,
    f12,
};

pub const Key = struct {
    mods: Modifiers = .{},
    code: KeyCode,

    pub fn format(this: @This(), writer: *std.io.Writer) std.io.Writer.Error!void {
        try writer.writeAll("Key{ ");
        var first = true;

        if (this.mods.shift or this.mods.alt or this.mods.ctrl) {
            try writer.writeAll("mods: ");
            try writer.print("{{shift: {}, alt: {}, ctrl: {}}}", .{ this.mods.shift, this.mods.alt, this.mods.ctrl });
            first = false;
        }

        if (!first) try writer.writeAll(", ");

        switch (this.code) {
            KeyCode.char => try writer.print("char: {u}", .{this.code.char}),
            else => try writer.print("code: {s}", .{@tagName(this.code)}),
        }

        try writer.writeAll(" }");
    }
};

pub const Event = union(enum) {
    key: Key,
    mouse: Mouse,
    resize,
    invalid,
    timeout,
    none,

    pub fn matchesChar(self: @This(), char: u21, mods: Modifiers) bool {
        switch (self) {
            .key => |k| switch (k.code) {
                .char => |c| {
                    return c == char and std.meta.eql(k.mods, mods);
                },
                else => return false,
            },
            else => return false,
        }
    }
};

// https://invisible-island.net/xterm/ctlseqs/ctlseqs.html#h2-Mouse-Tracking
pub const Mouse = struct {
    x: u16,
    y: u16,
    button: MouseButton,
    is_alt: bool,
    is_shift: bool,
    is_ctrl: bool,

    pub fn format(this: @This(), writer: *std.io.Writer) std.io.Writer.Error!void {
        try writer.writeAll("Mouse.");
        try writer.print("x: {d}, y: {d}, button: {any}, is_alt: {any}, is_shift: {any}, is_ctrl: {any}", .{ this.x, this.y, this.button, this.is_alt, this.is_shift, this.is_ctrl });
    }
};

pub const MouseButton = enum {
    left,
    middle,
    right,
    release,
    scroll_up,
    scroll_down,
    move,
    move_rightclick,
    __non_exhaustive,
};

/// Returns the next event received. If no event is received within the timeout,
/// it returns `.timeout`. Timeout is in miliseconds
///
/// When used in canonical mode, the user needs to press Enter to receive the event.
/// When raw terminal mode is activated, the function waits up to the specified timeout
/// for at least one event before returning.
pub fn nextWithTimeout(file: std.Io.File, timeout_ms: i32) !Event {
    switch (@import("builtin").os.tag) {
        .linux, .macos => return nextWithTimeoutPosix(file, timeout_ms),
        .windows => return nextWithTimeoutWindows(file, timeout_ms),
        else => return error.UnsupportedPlatform,
    }
}

fn nextWithTimeoutWindows(file: std.Io.File, timeout_ms: i32) !Event {
    const timeout: windows.DWORD = if (timeout_ms < 0) winapiGlue.INFINITE else @intCast(timeout_ms);
    const result = winapiGlue.WaitForSingleObject(file.handle, timeout);
    return switch (result) {
        winapiGlue.WAIT_OBJECT_0 => next(file),
        winapiGlue.WAIT_TIMEOUT_VAL => .timeout,
        else => error.WaitError,
    };
}

fn nextWithTimeoutPosix(file: std.Io.File, timeout_ms: i32) !Event {
    var polls: [1]std.posix.pollfd = .{.{
        .fd = file.handle,
        .events = std.posix.POLL.IN,
        .revents = 0,
    }};
    if ((try std.posix.poll(&polls, timeout_ms)) > 0) {
        return next(file);
    }

    return .timeout;
}

/// Returns true if there are events, false otherwise
fn terminalHasEvent(file: std.Io.File) !bool {
    switch (@import("builtin").os.tag) {
        .linux, .macos => {
            var polls: [1]std.posix.pollfd = .{.{
                .fd = file.handle,
                .events = std.posix.POLL.IN,
                .revents = 0,
            }};
            return (try std.posix.poll(&polls, 0)) > 0;
        },
        .windows => {
            const result = winapiGlue.WaitForSingleObject(file.handle, 0);
            return result == winapiGlue.WAIT_OBJECT_0;
        },
        else => return error.UnsupportedPlatform,
    }
}

fn readByteOrNull(reader: *std.Io.Reader) !?u8 {
    return reader.takeByte() catch |err| switch (err) {
        error.EndOfStream => null,
        else => return err,
    };
}

fn parseEscapeSequence(reader: *std.Io.Reader) !Event {
    const c1 = try readByteOrNull(reader) orelse return .invalid;

    switch (c1) {
        '[' => {
            const c2 = try readByteOrNull(reader) orelse return .invalid;
            switch (c2) {
                'A' => return Event{ .key = .{ .code = KeyCode.up } },
                'B' => return Event{ .key = .{ .code = KeyCode.down } },
                'C' => return Event{ .key = .{ .code = KeyCode.right } },
                'D' => return Event{ .key = .{ .code = KeyCode.left } },
                'Z' => return Event{ .key = .{ .code = KeyCode.tab, .mods = .{ .shift = true } } },
                '0'...'9' => {
                    // handle complex/large escape sequences
                    var buffer: [33]u8 = [_]u8{0} ** 33;
                    buffer[0] = c2;

                    var i: usize = 1;
                    while (i < 32) : (i += 1) {
                        const c = try readByteOrNull(reader) orelse break;
                        buffer[i] = c;
                        // read until we found a sequence terminator
                        if (c == '~' or c == 'M' or (c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z')) {
                            break;
                        }
                    }

                    i += 1;
                    buffer[i] = 0;

                    // special keys
                    if (std.mem.eql(u8, buffer[0..i], "1~")) {
                        return Event{ .key = .{ .code = .home } };
                    } else if (std.mem.eql(u8, buffer[0..1], "2~")) {
                        return Event{ .key = .{ .code = .insert } };
                    } else if (std.mem.eql(u8, buffer[0..i], "3~")) {
                        return Event{ .key = .{ .code = .delete } };
                    } else if (std.mem.eql(u8, buffer[0..i], "4~")) {
                        return Event{ .key = .{ .code = .end } };
                    } else if (std.mem.eql(u8, buffer[0..i], "5~")) {
                        return Event{ .key = .{ .code = .page_up } };
                    } else if (std.mem.eql(u8, buffer[0..i], "6~")) {
                        return Event{ .key = .{ .code = .page_down } };
                    }

                    // fn-keys
                    if (std.mem.eql(u8, buffer[0..i], "11~")) {
                        return Event{ .key = .{ .code = .f1 } };
                    } else if (std.mem.eql(u8, buffer[0..i], "12~")) {
                        return Event{ .key = .{ .code = .f2 } };
                    } else if (std.mem.eql(u8, buffer[0..i], "13~")) {
                        return Event{ .key = .{ .code = .f3 } };
                    } else if (std.mem.eql(u8, buffer[0..i], "14~")) {
                        return Event{ .key = .{ .code = .f4 } };
                    } else if (std.mem.eql(u8, buffer[0..i], "15~")) {
                        return Event{ .key = .{ .code = .f5 } };
                    } else if (std.mem.eql(u8, buffer[0..i], "17~")) {
                        return Event{ .key = .{ .code = .f6 } };
                    } else if (std.mem.eql(u8, buffer[0..i], "18~")) {
                        return Event{ .key = .{ .code = .f7 } };
                    } else if (std.mem.eql(u8, buffer[0..i], "19~")) {
                        return Event{ .key = .{ .code = .f8 } };
                    } else if (std.mem.eql(u8, buffer[0..i], "20~")) {
                        return Event{ .key = .{ .code = .f9 } };
                    } else if (std.mem.eql(u8, buffer[0..i], "21~")) {
                        return Event{ .key = .{ .code = .f10 } };
                    } else if (std.mem.eql(u8, buffer[0..i], "23~")) {
                        return Event{ .key = .{ .code = .f11 } };
                    } else if (std.mem.eql(u8, buffer[0..i], "24~")) {
                        return Event{ .key = .{ .code = .f12 } };
                    }

                    // Modified arrow keys - Shift (modifier 2)
                    if (std.mem.eql(u8, buffer[0..i], "1;2A")) {
                        return Event{ .key = .{ .code = .up, .mods = .{ .shift = true } } };
                    } else if (std.mem.eql(u8, buffer[0..i], "1;2B")) {
                        return Event{ .key = .{ .code = .down, .mods = .{ .shift = true } } };
                    } else if (std.mem.eql(u8, buffer[0..i], "1;2C")) {
                        return Event{ .key = .{ .code = .right, .mods = .{ .shift = true } } };
                    } else if (std.mem.eql(u8, buffer[0..i], "1;2D")) {
                        return Event{ .key = .{ .code = .left, .mods = .{ .shift = true } } };
                    }

                    // Modified arrow keys - Alt (modifier 3)
                    if (std.mem.eql(u8, buffer[0..i], "1;3A")) {
                        return Event{ .key = .{ .code = .up, .mods = .{ .alt = true } } };
                    } else if (std.mem.eql(u8, buffer[0..i], "1;3B")) {
                        return Event{ .key = .{ .code = .down, .mods = .{ .alt = true } } };
                    } else if (std.mem.eql(u8, buffer[0..i], "1;3C")) {
                        return Event{ .key = .{ .code = .right, .mods = .{ .alt = true } } };
                    } else if (std.mem.eql(u8, buffer[0..i], "1;3D")) {
                        return Event{ .key = .{ .code = .left, .mods = .{ .alt = true } } };
                    }

                    // Modified arrow keys - Shift+Alt (modifier 4)
                    if (std.mem.eql(u8, buffer[0..i], "1;4A")) {
                        return Event{ .key = .{ .code = .up, .mods = .{ .alt = true, .shift = true } } };
                    } else if (std.mem.eql(u8, buffer[0..i], "1;4B")) {
                        return Event{ .key = .{ .code = .down, .mods = .{ .alt = true, .shift = true } } };
                    } else if (std.mem.eql(u8, buffer[0..i], "1;4C")) {
                        return Event{ .key = .{ .code = .right, .mods = .{ .alt = true, .shift = true } } };
                    } else if (std.mem.eql(u8, buffer[0..i], "1;4D")) {
                        return Event{ .key = .{ .code = .left, .mods = .{ .alt = true, .shift = true } } };
                    }

                    // Modified arrow keys - Ctrl (modifier 5)
                    if (std.mem.eql(u8, buffer[0..i], "1;5A")) {
                        return Event{ .key = .{ .code = .up, .mods = .{ .ctrl = true } } };
                    } else if (std.mem.eql(u8, buffer[0..i], "1;5B")) {
                        return Event{ .key = .{ .code = .down, .mods = .{ .ctrl = true } } };
                    } else if (std.mem.eql(u8, buffer[0..i], "1;5C")) {
                        return Event{ .key = .{ .code = .right, .mods = .{ .ctrl = true } } };
                    } else if (std.mem.eql(u8, buffer[0..i], "1;5D")) {
                        return Event{ .key = .{ .code = .left, .mods = .{ .ctrl = true } } };
                    }

                    // Modified arrow keys - Ctrl+Shift (modifier 6)
                    if (std.mem.eql(u8, buffer[0..i], "1;6A")) {
                        return Event{ .key = .{ .code = .up, .mods = .{ .ctrl = true, .shift = true } } };
                    } else if (std.mem.eql(u8, buffer[0..i], "1;6B")) {
                        return Event{ .key = .{ .code = .down, .mods = .{ .ctrl = true, .shift = true } } };
                    } else if (std.mem.eql(u8, buffer[0..i], "1;6C")) {
                        return Event{ .key = .{ .code = .right, .mods = .{ .ctrl = true, .shift = true } } };
                    } else if (std.mem.eql(u8, buffer[0..i], "1;6D")) {
                        return Event{ .key = .{ .code = .left, .mods = .{ .ctrl = true, .shift = true } } };
                    }

                    // Modified arrow keys - Ctrl+Alt (modifier 7)
                    if (std.mem.eql(u8, buffer[0..i], "1;7A")) {
                        return Event{ .key = .{ .code = .up, .mods = .{ .ctrl = true, .alt = true } } };
                    } else if (std.mem.eql(u8, buffer[0..i], "1;7B")) {
                        return Event{ .key = .{ .code = .down, .mods = .{ .ctrl = true, .alt = true } } };
                    } else if (std.mem.eql(u8, buffer[0..i], "1;7C")) {
                        return Event{ .key = .{ .code = .right, .mods = .{ .ctrl = true, .alt = true } } };
                    } else if (std.mem.eql(u8, buffer[0..i], "1;7D")) {
                        return Event{ .key = .{ .code = .left, .mods = .{ .ctrl = true, .alt = true } } };
                    }

                    // Modified arrow keys - Ctrl+Shift+Alt (modifier 8)
                    if (std.mem.eql(u8, buffer[0..i], "1;8A")) {
                        return Event{ .key = .{ .code = .up, .mods = .{ .ctrl = true, .alt = true, .shift = true } } };
                    } else if (std.mem.eql(u8, buffer[0..i], "1;8B")) {
                        return Event{ .key = .{ .code = .down, .mods = .{ .ctrl = true, .alt = true, .shift = true } } };
                    } else if (std.mem.eql(u8, buffer[0..i], "1;8C")) {
                        return Event{ .key = .{ .code = .right, .mods = .{ .ctrl = true, .alt = true, .shift = true } } };
                    } else if (std.mem.eql(u8, buffer[0..i], "1;8D")) {
                        return Event{ .key = .{ .code = .left, .mods = .{ .ctrl = true, .alt = true, .shift = true } } };
                    }
                },
                'M' => {
                    // parse mouse sequences (SGR format: <button>;x;y M/m)
                    const mouseAction = try readByteOrNull(reader);
                    const x = try readByteOrNull(reader);
                    const y = try readByteOrNull(reader);

                    if (x == null or y == null or mouseAction == null) {
                        return .invalid;
                    }

                    var mouse_event = parseMouseAction(mouseAction.?) catch {
                        return .invalid;
                    };

                    // x and y are 1-based
                    mouse_event.x = x.? - 32; // 0x20
                    mouse_event.y = y.? - 32; // 0x20

                    return Event{ .mouse = mouse_event };
                },

                else => return .invalid,
            }
        },
        // ss3 sequences
        'O' => {
            const c2 = try readByteOrNull(reader) orelse return .invalid;
            switch (c2) {
                'P' => return Event{ .key = .{ .code = .f1 } },
                'Q' => return Event{ .key = .{ .code = .f2 } },
                'R' => return Event{ .key = .{ .code = .f3 } },
                'S' => return Event{ .key = .{ .code = .f4 } },
                'H' => return Event{ .key = .{ .code = .home } },
                'F' => return Event{ .key = .{ .code = .end } },
                else => return .invalid,
            }
        },

        // ctrl + alt
        '\x01'...'\x0C', '\x0E'...'\x1A' => return Event{ .key = .{ .code = .{ .char = c1 + 0x60 }, .mods = .{ .ctrl = true, .alt = true } } },

        // alt
        else => return Event{ .key = .{ .code = .{ .char = c1 }, .mods = .{ .alt = true } } },
    }

    return .invalid;
}

/// Returns the next event received.
/// When used with canonical mode, the user needs to press enter to receive the event.
/// When raw term is activated it will block until read at least one event.
pub fn next(file: std.fs.File) !Event {
    var reader_buf: [1]u8 = undefined;
    var file_reader = file.reader(&reader_buf);
    const reader = &file_reader.interface;

    const c0 = try readByteOrNull(reader) orelse return .none;
    switch (c0) {
        // Handle escape sequences
        '\x1b' => {
            const has_events = try terminalHasEvent(file);
            if (!has_events) {
                return Event{ .key = .{ .code = .esc } };
            } else {
                return parseEscapeSequence(reader);
            }
        },

        // Handle control characters (and special characters derived)
        // Backspace
        '\x08', '\x7f' => return Event{ .key = .{ .code = .backspace } },

        // Tab
        '\x09' => return Event{ .key = .{ .code = .tab } },

        // Enter (LF / CR)
        '\x0a', '\x0d' => return Event{ .key = .{ .code = .enter } },

        // Ctrl+A..Ctrl+Z, excluding 0x08, 0x09, 0x0a, 0x0d
        '\x01'...'\x07', '\x0b'...'\x0c', '\x0e'...'\x1a' => {
            const key = Key{
                .mods = .{ .ctrl = true },
                .code = .{ .char = c0 + 'a' - 0x01 },
            };
            return Event{ .key = key };
        },

        // utf-8 characters
        else => {
            const len = try unicode.utf8ByteSequenceLength(c0);
            var buf: [4]u8 = undefined;
            buf[0] = c0;

            for (1..len) |i| {
                buf[i] = try readByteOrNull(reader) orelse return .invalid;
            }

            const ch = switch (len) {
                1 => buf[0],
                2 => try unicode.utf8Decode2(buf[0..2].*),
                3 => try unicode.utf8Decode3(buf[0..3].*),
                4 => try unicode.utf8Decode4(buf[0..4].*),
                else => unreachable,
            };

            if (ch >= 'A' and ch <= 'Z') {
                return Event{ .key = .{ .code = .{ .char = ch + 32 }, .mods = .{ .shift = true } } };
            }

            return Event{ .key = .{ .code = .{ .char = ch } } };
        },
    }

    return .invalid;
}

fn parseMouseAction(action: u8) !Mouse {
    // Normal tracking mode sends an escape sequence on both button press and
    // release.  Modifier key (shift, ctrl, meta) information is also sent.  It
    // is enabled by specifying parameter 1000 to DECSET.  On button press or
    // release, xterm sends CSI M CbCxCy.
    //
    // o   The low two bits of Cb encode button information:
    //
    //               0=MB1 pressed,
    //               1=MB2 pressed,
    //               2=MB3 pressed, and
    //               3=release.
    //
    // o   The next three bits encode the modifiers which were down when the
    //     button was pressed and are added together:
    //
    //               4=Shift,
    //               8=Meta, and
    //               16=Control.

    var mouse_event = Mouse{
        .x = 0,
        .y = 0,
        .button = MouseButton.left,
        .is_alt = false,
        .is_shift = false,
        .is_ctrl = false,
    };

    // modifiers
    mouse_event.is_shift = action & 0b0000_01000 != 0;
    mouse_event.is_alt = action & 0b0000_1000 != 0;
    mouse_event.is_ctrl = action & 0b0001_0000 != 0;

    if (action & 0b0100_0000 != 0) {
        // Click and move mouse results into the following events:
        // 1. Left/Middle/Right click
        // 2. Scroll up/down (where left click is scroll up and middle/right click is scroll down)
        //
        // So to get the "drag" event, it needs to be handled in the frontend
        // or the main application.

        // EDIT: ok, so right click and move has an own event
        // TODO: check mouse

        switch (action & 0b0000_0011) {
            0 => mouse_event.button = MouseButton.scroll_up,
            1 => mouse_event.button = MouseButton.scroll_down,
            2 => mouse_event.button = MouseButton.move_rightclick,
            3 => mouse_event.button = MouseButton.move,
            else => return error.InvalidMouseButton,
        }

        return mouse_event;
    }

    // button clicks
    mouse_event.button = switch (action & 0b0000_0011) {
        0 => MouseButton.left,
        1 => MouseButton.middle,
        2 => MouseButton.right,
        3 => MouseButton.release,

        else => return error.InvalidMouseButton,
    };

    return mouse_event;
}
