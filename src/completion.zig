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

//
// templates
//

const body_marker = "<BODY>";

const bash_template =
    \\declare -F _init_completion >/dev/null || return 2>/dev/null
    \\
    \\_tennis() {
    \\  local cur prev
    \\  _init_completion || return
    \\
    \\  case "${prev}" in
    \\    <BODY>
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
    \\    <BODY>
    \\    '*:file:_files -g "*.csv(-.)" "*(-/)"'
    \\}
    \\
    \\if [ "$funcstack[1]" = "_tennis" ]; then
    \\  _tennis
    \\fi
    \\
;

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
    var body: std.ArrayList(u8) = .empty;
    defer body.deinit(alloc);
    var body_writer = body.writer(alloc);

    for (options.items[0..options.len]) |opt| {
        if (opt.value_name == null) continue;
        const values = valuesFor(.bash, opt.long);

        try body_writer.writeAll("    ");
        try writeBashPattern(&body_writer, opt);

        if (values) |v| {
            try body_writer.print(") COMPREPLY=($(compgen -W \"{s}\" -- \"${{cur}}\")) ; return ;;\n", .{v});
        } else {
            try body_writer.writeAll(") COMPREPLY=() ; return ;;\n");
        }
    }

    try body_writer.writeAll(
        \\  esac
        \\
        \\  if [[ "${cur}" == -* ]]; then
        \\    COMPREPLY=($(compgen -W "
    );

    for (options.items[0..options.len]) |opt| {
        if (opt.short) |short| try body_writer.print("{s} ", .{short});
        try body_writer.writeAll(opt.long);
        try body_writer.writeByte(' ');
    }

    try body_writer.writeAll(
        \\\"-- "${cur}"))
        \\  else
        \\    _filedir csv
        \\    [[ ${#COMPREPLY[@]} -eq 0 ]] && _filedir
        \\  fi
    );
    try writeWithMarker(writer, bash_template, body.items);
}

fn writeZsh(alloc: std.mem.Allocator, writer: anytype, options: Options) !void {
    var body: std.ArrayList(u8) = .empty;
    defer body.deinit(alloc);
    var body_writer = body.writer(alloc);

    for (options.items[0..options.len]) |opt| {
        const values = valuesFor(.zsh, opt.long);
        const value_label = if (opt.value_name) |str| std.mem.trim(u8, str, "<>") else null;

        if (opt.short) |short| {
            try body_writer.print("    '({s} {s})'{{{s},{s}}}'[{s}]'", .{
                short,
                opt.long,
                short,
                opt.long,
                opt.desc,
            });
        } else {
            try body_writer.print("    '{s}[{s}]'", .{ opt.long, opt.desc });
        }

        if (value_label) |label| {
            try body_writer.print(":{s}", .{label});
            if (values) |v| {
                try body_writer.print(":({s})", .{v});
            } else {
                try body_writer.writeByte(':');
            }
        }

        try body_writer.writeAll(" \\\n");
    }

    try writeWithMarker(writer, zsh_template, body.items);
}

fn writeWithMarker(writer: anytype, template: []const u8, body: []const u8) !void {
    const marker = std.mem.indexOf(u8, template, body_marker).?;
    try writer.writeAll(template[0..marker]);
    try writer.writeAll(util.strip(u8, body));
    try writer.writeAll(template[marker + body_marker.len ..]);
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

fn writeBashPattern(writer: anytype, opt: Option) !void {
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
    const out = try renderForTest(std.testing.allocator, .bash);
    defer std.testing.allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "--completion") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "with_love") != null);
}

test "writes zsh completion" {
    const out = try renderForTest(std.testing.allocator, .zsh);
    defer std.testing.allocator.free(out);
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
const util = @import("util.zig");
