// Generate shell completions from args.help plus a few value-completion tables.

//
// parse these from args.help
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

const body_marker = "<BODY>";

const bash_template =
    \\# bail without bash-completion
    \\declare -F _init_completion >/dev/null || return 2>/dev/null
    \\
    \\_tennis() {
    \\  local cur prev
    \\  _init_completion || return
    \\
    \\  case "${prev}" in
    \\
    \\<BODY>
    \\}
    \\
    \\complete -F _tennis tennis
    \\
;

const zsh_template =
    \\#compdef tennis
    \\compdef _tennis tennis
    \\
    \\_tennis() {
    \\  # -s "Enable option stacking for single-letter options"
    \\  _arguments -s \
    \\
    \\<BODY>
    \\    '*:file:_files -g "*.csv(-.)" "*(-/)"'
    \\}
    \\
    \\if [ "$funcstack[1]" = "_tennis" ]; then
    \\  _tennis
    \\fi
    \\
;

// main entry point
pub fn write(writer: *std.Io.Writer, shell: args.CompletionShell) !void {
    const options = parseOptions();
    switch (shell) {
        .bash => try writeBash(writer, options.items[0..options.len]),
        .zsh => try writeZsh(writer, options.items[0..options.len]),
    }
}

fn writeBash(writer: *std.Io.Writer, options: []const Option) !void {
    const marker = std.mem.indexOf(u8, bash_template, body_marker).?;
    try writer.writeAll(bash_template[0..marker]);

    for (options) |opt| {
        if (opt.value_name == null) continue;
        const values = valuesFor(.bash, opt.long);
        if (values) |v| {
            try writer.writeAll("    ");
            try writeBashPattern(writer, opt);
            try writer.print(") COMPREPLY=($(compgen -W \"{s}\" -- \"${{cur}}\")) ; return ;;\n", .{v});
        } else {
            try writer.writeAll("    ");
            try writeBashPattern(writer, opt);
            try writer.writeAll(") COMPREPLY=() ; return ;;\n");
        }
    }

    try writer.writeAll(
        \\  esac
        \\
        \\  if [[ "${cur}" == -* ]]; then
        \\    COMPREPLY=($(compgen -W "
    );

    for (options) |opt| {
        if (opt.short) |short| try writer.print("{s} ", .{short});
        try writer.writeAll(opt.long);
        try writer.writeByte(' ');
    }

    try writer.writeAll(
        \\\"-- "${cur}"))
        \\  else
        \\    _filedir csv
        \\    [[ ${#COMPREPLY[@]} -eq 0 ]] && _filedir
        \\  fi
    );
    try writer.writeAll(bash_template[marker + body_marker.len ..]);
}

fn writeZsh(writer: *std.Io.Writer, options: []const Option) !void {
    const marker = std.mem.indexOf(u8, zsh_template, body_marker).?;
    try writer.writeAll(zsh_template[0..marker]);

    for (options) |opt| {
        const values = valuesFor(.zsh, opt.long);
        const value_label = if (opt.value_name) |name| trimAngles(name) else null;

        if (opt.short) |short| {
            try writer.print("    '({s} {s})'{{{s},{s}}}'[{s}]'", .{
                short,
                opt.long,
                short,
                opt.long,
                opt.desc,
            });
        } else {
            try writer.print("    '{s}[{s}]'", .{ opt.long, opt.desc });
        }

        if (value_label) |label| {
            try writer.print(":{s}", .{label});
            if (values) |v| {
                try writer.print(":({s})", .{v});
            } else {
                try writer.writeByte(':');
            }
        }

        try writer.writeAll(" \\\n");
    }

    try writer.writeAll(zsh_template[marker + body_marker.len ..]);
}

// Parse all option rows out of args.help into short/long/value/description pieces.
fn parseOptions() Options {
    var out: Options = .{ .items = undefined, .len = 0 };
    var it = std.mem.splitScalar(u8, args.help, '\n');
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

    return .{
        .short = short,
        .long = long,
        .value_name = value_name,
        .desc = desc,
    };
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

fn trimAngles(value_name: []const u8) []const u8 {
    return std.mem.trim(u8, value_name, "<>");
}

fn writeBashPattern(writer: *std.Io.Writer, opt: Option) !void {
    if (opt.short) |short| {
        try writer.print("{s}|{s}", .{ short, opt.long });
    } else {
        try writer.writeAll(opt.long);
    }
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
    var buf: [8192]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    try write(&writer, .bash);
    try std.testing.expect(std.mem.indexOf(u8, writer.buffered(), "--completion") != null);
    try std.testing.expect(std.mem.indexOf(u8, writer.buffered(), "with_love") != null);
}

test "writes zsh completion" {
    var buf: [8192]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    try write(&writer, .zsh);
    try std.testing.expect(std.mem.indexOf(u8, writer.buffered(), "--completion[Print a shell completion script") != null);
}

const args = @import("args.zig");
const border = @import("border.zig");
const std = @import("std");
const types = @import("types.zig");
