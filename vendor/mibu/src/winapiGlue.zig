const std = @import("std");
const builtin = @import("builtin");
const windows = std.os.windows;
const kernel32 = windows.kernel32;

pub const WAIT_OBJECT_0 = windows.WAIT_OBJECT_0;
pub const WAIT_TIMEOUT_VAL = windows.WAIT_TIMEOUT;
pub const INFINITE = windows.INFINITE;
pub const WaitForSingleObject = kernel32.WaitForSingleObject;

pub const ENABLE_PROCESSED_OUTPUT: windows.DWORD = 0x0001;
pub const ENABLE_VIRTUAL_TERMINAL_PROCESSING: windows.DWORD = 0x0004;
pub const ENABLE_WINDOW_INPUT: windows.DWORD = 0x0008;
pub const ENABLE_MOUSE_INPUT: windows.DWORD = 0x0010;
pub const ENABLE_VIRTUAL_TERMINAL_INPUT: windows.DWORD = 0x0200;

pub const DISABLE_NEWLINE_AUTO_RETURN: windows.DWORD = 0x0008;

// https://learn.microsoft.com/en-us/windows/console/getconsolemode
pub fn getConsoleMode(handle: windows.HANDLE) !windows.DWORD {
    var mode: windows.DWORD = 0;

    // nonzero value means success
    if (kernel32.GetConsoleMode(handle, &mode) == 0) {
        const err = kernel32.GetLastError();
        return windows.unexpectedError(err);
    }

    return mode;
}

pub fn setConsoleMode(handle: windows.HANDLE, mode: windows.DWORD) !void {
    // nonzero value means success
    if (kernel32.SetConsoleMode(handle, mode) == 0) {
        const err = kernel32.GetLastError();
        return windows.unexpectedError(err);
    }
}

pub fn getConsoleScreenBufferInfo(handle: windows.HANDLE) !windows.CONSOLE.USER_IO.INFO.SCREEN_BUFFER {
    var get_console_info = windows.CONSOLE.USER_IO.GET_SCREEN_BUFFER_INFO;
    const file: std.Io.File = .{ .handle = handle, .flags = .{ .nonblocking = false } };
    return switch (try get_console_info.operate(std.Options.debug_io, file)) {
        .SUCCESS => get_console_info.Data,
        else => error.Unexpected,
    };
}
