//
// parse these from Args.help
//

const Option = struct {
    short: ?[]const u8,
    long: []const u8,
    value_name: ?[]const u8,
    desc: []const u8,
};

const Options = struct {
    items: [16]Option,
    len: usize,
};

// main entry point
pub fn write(alloc: std.mem.Allocator, shell: args.CompletionShell) !void {
    const options = parseOptions();
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(alloc);
    var buf_writer = buf.writer(alloc);

    switch (shell) {
        .bash => try writeBash(alloc, &buf_writer, options),
        .zsh => try writeZsh(alloc, &buf_writer, options),
    }
    try std.fs.File.stdout().writeAll(buf.items);
}

fn writeBash(alloc: std.mem.Allocator, writer: anytype, options: Options) !void {
    _ = alloc;
    try writer.writeAll(
        \\declare -F _init_completion >/dev/null || return 2>/dev/null
        \\
        \\_tennis() {
        \\  local cur prev
        \\  _init_completion || return
        \\
        \\  case "${prev}" in
    );

    for (options.items[0..options.len]) |opt| {
        if (opt.value_name == null) continue;
        const values = valuesFor(.bash, opt.long);

        try writer.writeAll("    ");
        try writePattern(writer, opt);

        if (values) |v| {
            try writer.print(") COMPREPLY=($(compgen -W \"{s}\" -- \"${{cur}}\")) ; return ;;\n", .{v});
        } else {
            try writer.writeAll(") COMPREPLY=() ; return ;;\n");
        }
    }

    try writer.writeAll(
        \\  esac
        \\
        \\  if [[ "${cur}" == -* ]]; then
        \\    COMPREPLY=($(compgen -W "
    );

    for (options.items[0..options.len]) |opt| {
        if (opt.short) |short| try writer.print("{s} ", .{short});
        try writer.writeAll(opt.long);
        try writer.writeByte(' ');
    }

    try writer.writeAll(
        \\" -- "${cur}"))
        \\  else
        \\    _filedir csv
        \\    [[ ${#COMPREPLY[@]} -eq 0 ]] && _filedir
        \\  fi
        \\}
        \\
        \\complete -F _tennis tennis
        \\
    );
}

fn writeZsh(alloc: std.mem.Allocator, writer: anytype, options: Options) !void {
    _ = alloc;
    try writer.writeAll(
        \\#compdef tennis
        \\compdef _tennis tennis
        \\
    );
    try writer.writeAll("_tennis() {\n");
    try writer.writeAll("  _arguments -s \\\n");

    for (options.items[0..options.len]) |opt| {
        if (opt.short) |short| {
            try writer.writeAll("    ");
            try writeZshSpec(writer, short, opt.desc, opt.value_name, valuesFor(.zsh, opt.long));
            try writer.writeAll(" \\\n");
        }
        try writer.writeAll("    ");
        try writeZshSpec(writer, opt.long, opt.desc, opt.value_name, valuesFor(.zsh, opt.long));
        try writer.writeAll(" \\\n");
    }

    try writer.writeAll(
        \\    '*:file:_files'
        \\}
        \\
        \\if [ "$funcstack[1]" = "_tennis" ]; then
        \\  _tennis
        \\fi
        \\
    );
}

fn writeZshSpec(
    writer: anytype,
    name: []const u8,
    desc: []const u8,
    value_name: ?[]const u8,
    values: ?[]const u8,
) !void {
    try writer.print("'{s}[{s}]", .{ name, desc });
    if (value_name) |value| {
        try writer.print(":{s}", .{std.mem.trim(u8, value, "<>")});
        if (values) |v| {
            try writer.writeByte(':');
            try writeZshValues(writer, v);
        } else {
            try writer.writeByte(':');
        }
    }
    try writer.writeByte('\'');
}

// Parse all option rows out of args.help into short/long/value/description pieces.
fn parseOptions() Options {
    var out: Options = .{ .items = undefined, .len = 0 };
    var it = std.mem.splitScalar(u8, args.Args.help, '\n');
    while (it.next()) |line| {
        const opt = parseOption(line) orelse continue;
        out.items[out.len] = opt;
        out.len += 1;
    }
    return out;
}

// Parse one help row like `-d, --delimiter <char>   description`.
fn parseOption(line: []const u8) ?Option {
    const trimmed = std.mem.trimLeft(u8, line, " ");
    if (trimmed.len == 0 or trimmed[0] != '-') return null;

    // Help rows use a run of spaces to separate the option spec from the description.
    const desc_start = std.mem.indexOf(u8, trimmed, "  ") orelse return null;
    const spec = std.mem.trimRight(u8, trimmed[0..desc_start], " ");
    const desc = std.mem.trimLeft(u8, trimmed[desc_start..], " ");

    var short: ?[]const u8 = null;
    var long_and_value = spec;
    if (std.mem.indexOf(u8, spec, ", ")) |comma| {
        short = spec[0..comma];
        long_and_value = spec[comma + 2 ..];
    }

    var long = long_and_value;
    var value_name: ?[]const u8 = null;
    if (std.mem.indexOfScalar(u8, long_and_value, ' ')) |space| {
        long = long_and_value[0..space];
        value_name = long_and_value[space + 1 ..];
    }

    return .{ .short = short, .long = long, .value_name = value_name, .desc = desc };
}

// Enum-backed options come from Zig enums; only digits and delimiter stay hardcoded.
fn valuesFor(shell: args.CompletionShell, long: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, long, "--border")) return enumValues(border.BorderName);
    if (std.mem.eql(u8, long, "--color")) return enumValues(types.Color);
    if (std.mem.eql(u8, long, "--completion")) return enumValues(args.CompletionShell);
    if (std.mem.eql(u8, long, "--delimiter")) {
        return if (shell == .zsh) "tab , \\; \\|" else ", ; | tab";
    }
    if (std.mem.eql(u8, long, "--digits")) return "1 2 3 4 5 6";
    if (std.mem.eql(u8, long, "--theme")) return enumValues(types.Theme);
    return null;
}

fn writePattern(writer: anytype, opt: Option) !void {
    if (opt.short) |short| {
        try writer.print("{s}|{s}", .{ short, opt.long });
    } else {
        try writer.writeAll(opt.long);
    }
}

fn writeZshValues(writer: anytype, values: []const u8) !void {
    try writer.writeByte('(');
    var it = std.mem.tokenizeScalar(u8, values, ' ');
    var first = true;
    while (it.next()) |value| {
        if (!first) try writer.writeByte(' ');
        first = false;
        if (std.mem.eql(u8, value, ";") or std.mem.eql(u8, value, "|")) {
            try writer.print("\\{s}", .{value});
        } else {
            try writer.writeAll(value);
        }
    }
    try writer.writeByte(')');
}

fn enumValues(comptime T: type) []const u8 {
    return comptime blk: {
        const fields = @typeInfo(T).@"enum".fields;
        var text: []const u8 = "";
        for (fields, 0..) |field, ii| {
            if (ii > 0) text = text ++ " ";
            text = text ++ field.name;
        }
        break :blk text;
    };
}

//
// testing
//

test "writes bash completion" {
    const out = try renderForTest(std.testing.allocator, .bash);
    defer std.testing.allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "--completion") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "with_love") != null);
}

test "writes zsh completion" {
    const out = try renderForTest(std.testing.allocator, .zsh);
    defer std.testing.allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "_arguments -s") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "--completion[Print a shell completion script") != null);
}

fn renderForTest(alloc: std.mem.Allocator, shell: args.CompletionShell) ![]u8 {
    const options = parseOptions();
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(alloc);
    var writer = buf.writer(alloc);

    switch (shell) {
        .bash => try writeBash(alloc, &writer, options),
        .zsh => try writeZsh(alloc, &writer, options),
    }
    return buf.toOwnedSlice(alloc);
}

const args = @import("args.zig");
const border = @import("border.zig");
const std = @import("std");
const types = @import("types.zig");
