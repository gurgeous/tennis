#!/usr/bin/env bats

# Bats is for process-level behavior that Rust unit tests do not cover well:
# real CLI IO, tty/pager behavior, shell scripts, env handling, subprocesses,
# and one canonical known-good render through the compiled binary.

setup() {
  ROOT="$BATS_TEST_DIRNAME/.."
  BIN="$ROOT/target/debug/tennis"
}

# Strip \r before comparing to paper over unix/win newline issues
assert_output_matches() {
  [ "$(tr -d '\r' <<<"$output")" = "$(tr -d '\r' <<<"$1")" ]
}

run_ok() {
  run "$BIN" "$@"
  [ "$status" -eq 0 ]
}

run_tty() {
  if [[ "$(uname)" == Darwin ]]; then
    run script -q /dev/null bash -lc "$1"
  else
    run script -qfec "$1" /dev/null
  fi
}

#
# Golden e2e
#

# do not remove this golden e2e
@test "golden snapshot" {
  run_ok --color=on --theme dark --width 80 --title foo "$ROOT/tests/test.csv"
  assert_output_matches "$(printf '%b' "$(cat "$ROOT/tests/basic-color.out")")"
}

#
# CLI basics
#

@test "bad args and flags" {
  # unknown flag
  run "$BIN" --bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"unexpected argument '--bogus'"* ]]
  [[ "$output" == *"tennis: try 'tennis --help' for more information"* ]]
  [[ "$output" != *"Usage: tennis"* ]]
  [[ "$output" != *"tip:"* ]]

  # invalid enum
  run "$BIN" --color bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid value 'bogus' for '--color <color>'"* ]]

  # extra file
  run "$BIN" "$ROOT/tests/test.csv" bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"unexpected argument 'bogus'"* ]]
}

# bats test_tags=skipwin
@test "stdin not tty" {
  run_tty "'$BIN' --color=off"
  [ "$status" -eq 1 ]
  [[ "$output" == *"tennis: Could not read from stdin"* ]]
}

#
# Terminal IO
#

@test "stdin" {
  run bash -lc "cat '$ROOT/tests/test.csv' | '$BIN' --color=off --width 120"
  [ "$status" -eq 0 ]
  [[ "$output" == *"carat"* ]]
  [[ "$output" == *"Ideal"* ]]
  [[ "$output" == *"0.31"* ]]
  [[ "$output" == *"344"* ]]
}

# bats test_tags=skipwin
@test "tty width" {
  run_tty "stty rows 24 cols 37; printf 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa,bbbbbbbbbbbbbbbbbbbb,cccccccccc\nx,y,z\n' | '$BIN' --color=off"
  [ "$status" -eq 0 ]
  [[ "$output" == *"aaaaaaa…"* ]]
  [[ "$output" != *"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"* ]]
}

@test "short pipe" {
  run bash -o pipefail -lc "'$BIN' --color=off --width 80 '$ROOT/tests/test.csv' | sh -c 'exit 0'"
  [ "$status" -eq 0 ]
}

#
# Input errors
#

@test "invalid input" {
  # invalid csv
  run bash -lc "printf 'a,b\n\"oops\n' | '$BIN' --color=off"
  [ "$status" -eq 1 ]
  [[ "$output" == *"tennis:"* ]]

  # jagged csv
  run bash -lc "printf 'a,b\nc\n' | '$BIN' --color=off"
  [ "$status" -eq 1 ]
  [[ "$output" == *"tennis: All csv rows must have same number of columns"* ]]

  # invalid utf8
  run bash -lc "printf 'a,b\n\xff,2\n' | '$BIN' --color=off --width 80"
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\xef\xbf\xbd'* ]]
}

#
# Input formats
#

@test "delims" {
  # file
  run_ok --color=off --width 80 "$ROOT/tests/semicolon.csv"
  [[ "$output" == *"alice"* ]]
  [[ "$output" == *"1,234"* ]]
  [[ "$output" == *"denver"* ]]

  # stdin
  run bash -lc "cat '$ROOT/tests/semicolon.csv' | '$BIN' --color=off --width 80"
  [ "$status" -eq 0 ]
  [[ "$output" == *"alice"* ]]
  [[ "$output" == *"1,234"* ]]
  [[ "$output" == *"denver"* ]]

  # explicit delimiter overrides sniffing"
  run_ok --color=off --width 80 --delimiter ',' "$ROOT/tests/semicolon.csv"
  [[ "$output" == *"name;score;city"* ]]
  [[ "$output" == *"alice;1234;boston"* ]]
}

@test "json" {
  # array
  run_ok --color=off --width 80 "$ROOT/tests/test.json"
  [[ "$output" == *"alice"* ]]
  [[ "$output" == *"bob"* ]]
  [[ "$output" == *"{\"ok\":true}"* ]]
  [[ "$output" == *"[\"a\", \"b\"]"* ]]

  # object
  run_ok --color=off --width 80 "$ROOT/tests/test-jsono.json"
  [[ "$output" == *"key"* ]]
  [[ "$output" == *"value"* ]]
  [[ "$output" == *"name"* ]]
  [[ "$output" == *"alice"* ]]
  [[ "$output" == *"{\"ok\":true}"* ]]

  # jsonl
  run_ok --color=off --width 80 "$ROOT/tests/test.jsonl"
  [[ "$output" == *"alice"* ]]
  [[ "$output" == *"bob"* ]]
  [[ "$output" == *"{\"ok\":true}"* ]]

  # ndjson
  run_ok --color=off --width 80 --head 2 "$ROOT/tests/test.ndjson"
  [[ "$output" == *"alice"* ]]
  [[ "$output" == *"1,234"* ]]
  [[ "$output" == *"bob"* ]]
  [[ "$output" != *"cara"* ]]
}

@test "unicode" {
  run_ok --color=off --width 40 "$ROOT/tests/unicode.csv"
  [[ "$output" == *"│ accent    │ café noir"* ]]
  [[ "$output" == *"│ heart     │ I ❤️ Rust"* ]]
  [[ "$output" == *"│ skin_tone │ thumbs 👍🏽…"* || "$output" == *"│ skin_tone │ thumbs 👍…"* || "$output" == *"│ skin_tone │ thumbs 👍🏽 …"* ]]
  [[ "$output" == *"│ family    │ family 👨‍👩‍👧‍👦…"* || "$output" == *"│ family    │ family 👨‍…"* || "$output" == *"│ family    │ family 👨‍👩‍👧‍👦 …"* ]]
  [[ "$output" == *"│ flag      │ go 🇺🇸 now"* ]]

  run_ok --color=off --width 80 "$ROOT/tests/cjk.csv"
  [[ "$output" == *"香港"* ]]
  [[ "$output" == *"英皇書院同學會小學"* ]]
}

#
# SQLite
#

# bats test_tags=skipwin
@test "sqlite" {
  # basic
  run_ok --color=off --width 80 "$ROOT/tests/sqlite-single.db"
  [[ "$output" == *"name"* ]]
  [[ "$output" == *"score"* ]]
  [[ "$output" == *"alice"* ]]
  [[ "$output" == *"cara"* ]]

  # sqlite magic number
  local db
  db="$BATS_TEST_TMPDIR/sqlite-single.bin"
  cp "$ROOT/tests/sqlite-single.db" "$db"
  run_ok --color=off --width 80 "$db"
  [[ "$output" == *"name"* ]]
  [[ "$output" == *"score"* ]]
  [[ "$output" == *"alice"* ]]
  [[ "$output" == *"cara"* ]]

  # sqlite largest table
  run_ok --color=off --width 80 "$ROOT/tests/sqlite-multi.db"
  [[ "$output" == *"name"* ]]
  [[ "$output" == *"score"* ]]
  [[ "$output" == *"alice"* ]]
  [[ "$output" == *"cara"* ]]
  [[ "$output" != *"solo"* ]]

  # sqlite --table
  run_ok --color=off --width 80 --table PLAYERS "$ROOT/tests/sqlite-single.db"
  [[ "$output" == *"name"* ]]
  [[ "$output" == *"score"* ]]
  [[ "$output" == *"alice"* ]]
  [[ "$output" == *"cara"* ]]

  # sqlite invalid --table
  run "$BIN" --color=off --width 80 --table missing "$ROOT/tests/sqlite-single.db"
  [ "$status" -eq 1 ]
  [[ "$output" == *"tennis: Table 'missing' was not found in that sqlite file."* ]]
  [[ "$output" == *$'tennis: Here are the tables in that file:\ntennis:   players'* ]]

  # --tabile w/o sqlite
  run "$BIN" --color=off --width 80 --table players "$ROOT/tests/test.csv"
  [ "$status" -eq 1 ]
  [[ "$output" == *"tennis: --table only works with sqlite files"* ]]

  # invalid sqlite file
  run "$BIN" --color=off --width 80 "$ROOT/tests/sqlite-invalid.db"
  [ "$status" -eq 1 ]
  [[ "$output" == *"tennis: Could not read that file with sqlite3"* ]]

  # missing sqlite3
  run env PATH= "$BIN" --color=off --width 80 "$ROOT/tests/sqlite-single.db"
  [ "$status" -eq 1 ]
  [[ "$output" == *"tennis: \`sqlite3\` is required, but I couldn't find it."* ]]
}

#
# flags
#

@test "-b/-bb/-bbb" {
  # default
  run_ok --color=off --width 80 "$ROOT/tests/test.csv"
  [[ "$output" == *"Ide…"* ]]
  [[ "$output" != *"Ideal"* ]]

  # -b
  run_ok --color=off --width 80 -b cut "$ROOT/tests/test.csv"
  [[ "$output" == *"Ideal"* ]]

  # -bb
  run_ok --color=off --width 80 -bb cut "$ROOT/tests/test.csv"
  [[ "$output" == *"Ideal"* ]]

  # -bbb
  run_ok --color=off --width 80 -bbb cut "$ROOT/tests/test.csv"
  [[ "$output" == *"Very Good"* ]]

  # invalid column
  run "$BIN" --color=off --width 80 -b bogus "$ROOT/tests/test.csv"
  [ "$status" -eq 1 ]
  [[ "$output" == *"tennis: -b/-bb/-bbb didn't look right, should be a comma-separated list of columns."* ]]
  [[ "$output" == *"tennis: You wrote: bogus"* ]]
  [[ "$output" == *$'tennis: Here are the columns in that file:\ntennis:   carat\ntennis:   cut'* ]]
  [[ "$output" == *"tennis: try 'tennis --help' for more information"* ]]
}

@test "--scale and --rscale" {
  # scale
  run_ok --color=on --theme dark --width 80 --scale carat "$ROOT/tests/test.csv"
  [[ "$output" == *$'\e[48;2;'* ]]

  # reverse scale
  run_ok --color=on --theme dark --width 80 --rscale carat "$ROOT/tests/test.csv"
  [[ "$output" == *$'\e[48;2;'* ]]

  # invalid column
  run "$BIN" --color=off --width 80 --scale bogus "$ROOT/tests/test.csv"
  [ "$status" -eq 1 ]
  [[ "$output" == *"tennis: color scale didn't look right, should be a comma-separated list of columns."* ]]
  [[ "$output" == *"tennis: You wrote: bogus"* ]]
}

@test "--color" {
  # default color is on, even through a pipe
  run env -u NO_COLOR "$BIN" --theme dark --width 80 "$ROOT/tests/test.csv"
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\e['* ]]

  # no color
  run env NO_COLOR=1 "$BIN" --width 80 "$ROOT/tests/test.csv"
  [ "$status" -eq 0 ]
  [[ "$output" != *$'\e['* ]]

  # explicit color
  run env NO_COLOR=1 "$BIN" --color=on --width 80 "$ROOT/tests/test.csv"
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\e['* ]]

  # auto pipe
  run env -u NO_COLOR "$BIN" --color=auto --theme dark --width 80 "$ROOT/tests/test.csv"
  [ "$status" -eq 0 ]
  [[ "$output" != *$'\e['* ]]
}

# bats test_tags=skipwin
@test "--color tty" {
  run_tty "stty rows 24 cols 80; env -u NO_COLOR '$BIN' --color=auto --theme dark --width 80 '$ROOT/tests/test.csv'"
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\e['* ]]
}

@test "--completion" {
  # bash
  run_ok --completion bash
  [[ "$output" == *"complete -F _tennis tennis"* ]]
  [[ "$output" == *"-bb -bbb"* ]]
  [[ "$output" == *"--scale"* ]]
  [[ "$output" == *"--rscale"* ]]
  [[ "$output" != *"--_b2"* ]]
  [[ "$output" == *"@(csv|tsv|"* ]]

  run bash -lc "set -o pipefail; \"$BIN\" --completion bash | bash -n"
  [ "$status" -eq 0 ]

  # zsh
  run_ok --completion zsh
  [[ "$output" == *"#compdef tennis"* ]]
  [[ "$output" == *"--scale"* ]]
  [[ "$output" == *"--rscale"* ]]
  [[ "$output" != *"--_b2"* ]]
  [[ "$output" == *"_files -g \"*.(csv|tsv|"* ]]

  command -v zsh >/dev/null || skip "zsh not installed"
  run bash -lc "set -o pipefail; \"$BIN\" --completion zsh | zsh -n"
  [ "$status" -eq 0 ]
}

@test "--head and --tail" {
  # head
  run_ok --color=off --width 120 --head 2 "$ROOT/tests/test.csv"
  [[ "$output" == *"Ideal"* ]]
  [[ "$output" == *"Premi"* ]]
  [[ "$output" != *"Very Good"* ]]

  # tail
  run_ok --color=off --width 80 -n --tail 2 "$ROOT/tests/test.csv"
  [[ "$output" == *"│  1 │"* ]]
  [[ "$output" == *"│  2 │"* ]]
  [[ "$output" != *"│ 13 │"* ]]

  # conflict
  run "$BIN" --head 2 --tail 2 "$ROOT/tests/test.csv"
  [ "$status" -eq 1 ]
  [[ "$output" == *"cannot be used with"* ]]
  [[ "$output" == *"--head <int>"* ]]
  [[ "$output" == *"--tail <int>"* ]]
}

@test "--help and --version" {
  run_ok --help
  [[ "$output" == *"Usage: tennis [OPTIONS] [FILE]"* ]]
  [[ "$output" == *"Popular options:"* ]]
  [[ "$output" == *"Sort, filter, etc:"* ]]
  [[ "$output" == *"Other options:"* ]]
  [[ "$output" == *"-bb"* ]]
  [[ "$output" == *"-bbb"* ]]
  [[ "$output" == *"--scale"* ]]
  [[ "$output" == *"--rscale"* ]]

  run_ok --version
  [[ "$output" == tennis:* ]]
}

# bats test_tags=skipwin
@test "--help tty" {
  run_tty "'$BIN'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"tennis: try 'tennis --help' for more information"* ]]
}

# bats test_tags=skipwin
@test "--pager" {
  # cat pager
  run_tty "stty rows 24 cols 80; PAGER='cat -' '$BIN' --color=off --pager '$ROOT/tests/test.csv'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"carat"* ]]
  [[ "$output" == *"326"* ]]

  # quoted argv
  local out="$BATS_TEST_TMPDIR/pager.out"
  run_tty "stty rows 24 cols 80; PAGER='sh -c \"cat > $out\"' '$BIN' --color=off --pager '$ROOT/tests/test.csv'"
  [ "$status" -eq 0 ]
  [ -s "$out" ]
  grep -q "carat" "$out"

  # explicit --pager works even when stdout is not a tty
  out="$BATS_TEST_TMPDIR/pager-pipe.out"
  run bash -lc "PAGER='sh -c \"cat > $out\"' '$BIN' --color=off --pager '$ROOT/tests/test.csv' > '$BATS_TEST_TMPDIR/stdout.out'"
  [ "$status" -eq 0 ]
  [ -s "$out" ]
  [ ! -s "$BATS_TEST_TMPDIR/stdout.out" ]
  grep -q "carat" "$out"
}

@test "--pager rejects whitespace-only PAGER" {
  run env PAGER="   " "$BIN" --color=off --pager "$ROOT/tests/test.csv"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Could not start pager"* ]]
}

@test "--peek" {
  # sample stats
  run_ok --color=off --width 80 --peek "$ROOT/tests/test.json"
  [[ "$output" == *"3 rows × 5 cols"* ]]
  [[ "$output" == *"alice"* ]]
  [[ "$output" == *"│ column │ type"* ]]
  [[ "$output" == *"│ score  │ int"* ]]

  # footer
  run_ok --color=off --width 80 --peek "$ROOT/tests/test.csv"
  [[ "$output" == *"14 rows × 10 cols"* ]]
  [[ "$output" == *"… 9 more rows …"* ]]
  [[ "$output" == *"stats"* ]]

  # sample honors presentation flags
  run_ok --color=off --width 80 --peek --digits 1 -n "$ROOT/tests/test.csv"
  [[ "$output" == *"│ #  │ carat"* ]]
  [[ "$output" == *"│  1 │   0.2"* ]]

  # invalid big column
  run "$BIN" --color=off --width 80 --peek -b bogus "$ROOT/tests/test.csv"
  [ "$status" -eq 1 ]
  [[ "$output" == *"tennis: -b/-bb/-bbb didn't look right"* ]]
  [[ "$output" == *"tennis: You wrote: bogus"* ]]
}

@test "--select" {
  run_ok --color=off --width 80 --select score,name "$ROOT/tests/test.json"
  [[ "$output" == *"│ score │ name  │"* ]]
  [[ "$output" != *"city"* ]]

  run_ok --color=off --width 80 --select score,name --deselect score "$ROOT/tests/test.json"
  [[ "$output" == *"│ name  │"* ]]
  [[ "$output" == *"│ alice │"* ]]
  [[ "$output" != *"score"* ]]
}

@test "--sort" {
  # before head
  run_ok --color=off --width 80 --sort name --head 2 "$ROOT/tests/test.json"
  [[ "$output" == *"alice"* ]]
  [[ "$output" == *"bob"* ]]
  [[ "$output" != *"cara"* ]]

  # numeric csv
  run_ok --color=off --width 120 --sort price --head 1 "$ROOT/tests/test.csv"
  [[ "$output" == *"326"* ]]
  [[ "$output" == *"Ideal"* ]]

  # decimal csv
  run_ok --color=off --width 120 --sort carat --head 1 "$ROOT/tests/test.csv"
  [[ "$output" == *"0.210"* ]]
  [[ "$output" == *"Premium"* ]]
  [[ "$output" != *"0.300"* ]]

  # natural mixed
  run_ok --color=off --vanilla --width 120 --sort mixed --head 1 "$ROOT/tests/natsort.csv"
  [[ "$output" == *"theta"* ]]
  [[ "$output" == *"x02-y2"* ]]

  # natural float
  run_ok --color=off --vanilla --width 120 --sort float --head 1 "$ROOT/tests/natsort.csv"
  [[ "$output" == *"kappa"* ]]
  [[ "$output" == *"0.99"* ]]

  # invalid column
  run "$BIN" --color=off --sort version "$ROOT/tests/test.csv"
  [ "$status" -eq 1 ]
  [[ "$output" == *"tennis: --sort didn't look right, should be a comma-separated list of columns."* ]]
  [[ "$output" == *$'tennis: Here are the columns in that file:\ntennis:   carat\ntennis:   cut\ntennis:   color'* ]]
}

@test "--row-numbers" {
  run_ok --color=off --width 80 -n "$ROOT/tests/test.csv"
  [[ "$output" == *"│ #  │"* ]]
  [[ "$output" == *"│  1 │ 0.230 │"* ]]
  [[ "$output" == *"│ 14 │ 0.310 │"* ]]
}
