// Static shell completion emitters for the current CLI.

pub const Shell = enum { bash, zsh };

const bash =
    \\# bail without bash-completion
    \\declare -F _init_completion >/dev/null || return 2>/dev/null
    \\
    \\_tennis() {
    \\  local cur prev
    \\  _init_completion || return
    \\
    \\  case "${prev}" in
    \\    --border) COMPREPLY=($(compgen -W "ascii_rounded basic basic_compact compact compact_double dots double heavy light markdown none psql reinforced restructured rounded single thin with_love" -- "${cur}")) ; return ;;
    \\    --color) COMPREPLY=($(compgen -W "on off auto" -- "${cur}")) ; return ;;
    \\    --completion) COMPREPLY=($(compgen -W "bash zsh" -- "${cur}")) ; return ;;
    \\    --theme) COMPREPLY=($(compgen -W "auto dark light" -- "${cur}")) ; return ;;
    \\    -d|--delimiter) COMPREPLY=($(compgen -W ", ; | tab" -- "${cur}")) ; return ;;
    \\    --digits) COMPREPLY=($(compgen -W "1 2 3 4 5 6" -- "${cur}")) ; return ;;
    \\    -t|--title|-w|--width) COMPREPLY=() ; return ;;
    \\  esac
    \\
    \\  if [[ "${cur}" == -* ]]; then
    \\    COMPREPLY=($(compgen -W "-d --delimiter -n --row-numbers -t --title -w --width --border --color --completion --digits --theme --vanilla --help --version" -- "${cur}"))
    \\  else
    \\    _filedir csv
    \\    [[ ${#COMPREPLY[@]} -eq 0 ]] && _filedir
    \\  fi
    \\}
    \\
    \\complete -F _tennis tennis
    \\
;

const zsh =
    \\#compdef tennis
    \\compdef _tennis tennis
    \\
    \\_tennis() {
    \\  # -s "Enable option stacking for single-letter options"
    \\  _arguments -s \
    \\    '(-d --delimiter)'{-d,--delimiter}'[set field delimiter]:delimiter:(tab , \; \|)' \
    \\    '(-n --row-numbers)'{-n,--row-numbers}'[turn on row numbers]' \
    \\    '(-t --title)'{-t,--title}'[add a title to the table]:title:' \
    \\    '(-w --width)'{-w,--width}'[set max table width in chars]:width:' \
    \\    '--border[select table border style]:border:(ascii_rounded basic basic_compact compact compact_double dots double heavy light markdown none psql reinforced restructured rounded single thin with_love)' \
    \\    '--color[turn color off and on]:color:(on off auto)' \
    \\    '--completion[print a shell completion script]:shell:(bash zsh)' \
    \\    '--digits[digits after decimal for float columns]:digits:(1 2 3 4 5 6)' \
    \\    '--theme[select color theme]:theme:(auto dark light)' \
    \\    '--vanilla[disable numeric formatting entirely]' \
    \\    '--help[get help]' \
    \\    '--version[show version number]' \
    \\    '*:file:_files -g "*.csv(-.)" "*(-/)"'
    \\}
    \\
    \\if [ "$funcstack[1]" = "_tennis" ]; then
    \\  _tennis
    \\fi
    \\
;

pub fn write(writer: *std.Io.Writer, shell: Shell) !void {
    try writer.writeAll(switch (shell) {
        .bash => bash,
        .zsh => zsh,
    });
}

test "writes bash completion" {
    var buf: [4096]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    try write(&writer, .bash);
    try std.testing.expect(std.mem.indexOf(u8, writer.buffered(), "--completion") != null);
}

test "writes zsh completion" {
    var buf: [4096]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    try write(&writer, .zsh);
    try std.testing.expect(std.mem.indexOf(u8, writer.buffered(), "--completion") != null);
}

const std = @import("std");
