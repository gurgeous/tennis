#!/usr/bin/env bats

setup() {
  REPO_ROOT="$BATS_TEST_DIRNAME/.."
  TENNIS_BIN="$REPO_ROOT/zig-out/bin/tennis"
}

@test "rejects unknown flags" {
  run "$TENNIS_BIN" --bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"tennis: Invalid argument '--bogus'"* ]]
}

@test "rejects invalid enum values" {
  run "$TENNIS_BIN" --color bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"tennis: Error while parsing arguments: NameNotPartOfEnum"* ]]
}

@test "rejects extra file arguments" {
  run "$TENNIS_BIN" "$REPO_ROOT/testdata/test.csv" bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"tennis: Too many file arguments"* ]]
}

@test "prints help text" {
  run "$TENNIS_BIN" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: tennis [options...] <file.csv>"* ]]
  [[ "$output" == *"--border <border>"* ]]
  [[ "$output" == *"--completion <shell>"* ]]
  [[ "$output" == *"rounded|thin|double"* ]]
  [[ "$output" == *"--color <color>"* ]]
  [[ "$output" == *"--digits <int>"* ]]
  [[ "$output" == *"--deselect <headers>"* ]]
  [[ "$output" == *"--pager"* ]]
  [[ "$output" == *"--peek"* ]]
  [[ "$output" == *"--head <int>"* ]]
  [[ "$output" == *"--tail <int>"* ]]
  [[ "$output" == *"--zebra"* ]]
  [[ "$output" == *"--vanilla"* ]]
  [[ "$output" == *"--version"* ]]
}

@test "prints version" {
  run "$TENNIS_BIN" --version
  [ "$status" -eq 0 ]
  [[ "$output" == tennis:* ]]
}

@test "prints bash completion" {
  run "$TENNIS_BIN" --completion bash
  [ "$status" -eq 0 ]
  [[ "$output" == *"complete -F _tennis tennis"* ]]
}

@test "prints zsh completion" {
  run "$TENNIS_BIN" --completion zsh
  [ "$status" -eq 0 ]
  [[ "$output" == *"#compdef tennis"* ]]
}

@test "fails on invalid csv input" {
  run bash -lc "printf 'a,b\n\"oops\n' | '$TENNIS_BIN' --color=off"
  [ "$status" -eq 1 ]
  [[ "$output" == *"tennis: That CSV file doesn't look right"* ]]
}

@test "fails on jagged csv input" {
  run bash -lc "printf 'a,b\nc\n' | '$TENNIS_BIN' --color=off"
  [ "$status" -eq 1 ]
  [[ "$output" == *"tennis: All csv rows must have same number of columns"* ]]
}

@test "renders semicolon-delimited csv" {
  run bash -lc "printf 'name;score\nalice;1234\nbob;5678\n' | '$TENNIS_BIN' --color=off --delimiter ';' --width 80"
  [ "$status" -eq 0 ]
  [[ "$output" == *"name"* ]]
  [[ "$output" == *"score"* ]]
  [[ "$output" == *"alice"* ]]
  [[ "$output" == *"1,234"* ]]
  [[ "$output" == *"5,678"* ]]
}

@test "auto-detects semicolon csv from file" {
  run "$TENNIS_BIN" --color=off --width 80 "$REPO_ROOT/testdata/semicolon.csv"
  [ "$status" -eq 0 ]
  [[ "$output" == *"alice"* ]]
  [[ "$output" == *"1,234"* ]]
  [[ "$output" == *"denver"* ]]
}

@test "auto-detects semicolon csv from stdin" {
  run bash -lc "cat '$REPO_ROOT/testdata/semicolon.csv' | '$TENNIS_BIN' --color=off --width 80"
  [ "$status" -eq 0 ]
  [[ "$output" == *"alice"* ]]
  [[ "$output" == *"1,234"* ]]
  [[ "$output" == *"denver"* ]]
}

@test "auto-detects tab-delimited csv from file" {
  run "$TENNIS_BIN" --color=off --width 80 "$REPO_ROOT/testdata/test.tsv"
  [ "$status" -eq 0 ]
  [[ "$output" == *"carat"* ]]
  [[ "$output" == *"Ideal"* ]]
  [[ "$output" == *"344"* ]]
}

@test "auto-detects pipe-delimited csv from file" {
  run "$TENNIS_BIN" --color=off --width 80 "$REPO_ROOT/testdata/pipe.csv"
  [ "$status" -eq 0 ]
  [[ "$output" == *"alice"* ]]
  [[ "$output" == *"1,234"* ]]
  [[ "$output" == *"denver"* ]]
}

@test "renders json array input" {
  run "$TENNIS_BIN" --color=off --width 80 "$REPO_ROOT/testdata/test.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"alice"* ]]
  [[ "$output" == *"bob"* ]]
  [[ "$output" == *"{\"ok\":true}"* ]]
  [[ "$output" == *"[\"a\", \"b\"]"* ]]
}

@test "renders single json object input" {
  run "$TENNIS_BIN" --color=off --width 80 "$REPO_ROOT/testdata/test-jsono.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"key"* ]]
  [[ "$output" == *"value"* ]]
  [[ "$output" == *"name"* ]]
  [[ "$output" == *"alice"* ]]
  [[ "$output" == *"{\"ok\":true}"* ]]
}

@test "renders jsonl input" {
  run "$TENNIS_BIN" --color=off --width 80 "$REPO_ROOT/testdata/test.jsonl"
  [ "$status" -eq 0 ]
  [[ "$output" == *"alice"* ]]
  [[ "$output" == *"bob"* ]]
  [[ "$output" == *"{\"ok\":true}"* ]]
}

@test "renders ndjson input with head" {
  run "$TENNIS_BIN" --color=off --width 80 --head 2 "$REPO_ROOT/testdata/test.ndjson"
  [ "$status" -eq 0 ]
  [[ "$output" == *"alice"* ]]
  [[ "$output" == *"1,234"* ]]
  [[ "$output" == *"bob"* ]]
  [[ "$output" != *"cara"* ]]
}

@test "auto-detects json array from stdin" {
  run bash -lc "cat '$REPO_ROOT/testdata/test.json' | '$TENNIS_BIN' --color=off --width 80"
  [ "$status" -eq 0 ]
  [[ "$output" == *"alice"* ]]
  [[ "$output" == *"{\"ok\":true}"* ]]
}

@test "auto-detects single json object from stdin" {
  run bash -lc "cat '$REPO_ROOT/testdata/test-jsono.json' | '$TENNIS_BIN' --color=off --width 80"
  [ "$status" -eq 0 ]
  [[ "$output" == *"key"* ]]
  [[ "$output" == *"value"* ]]
  [[ "$output" == *"name"* ]]
  [[ "$output" == *"alice"* ]]
  [[ "$output" == *"{\"ok\":true}"* ]]
}

@test "auto-detects jsonl from stdin" {
  run bash -lc "cat '$REPO_ROOT/testdata/test.jsonl' | '$TENNIS_BIN' --color=off --width 80"
  [ "$status" -eq 0 ]
  [[ "$output" == *"alice"* ]]
  [[ "$output" == *"bob"* ]]
}

@test "explicit delimiter overrides sniffing" {
  run "$TENNIS_BIN" --color=off --width 80 --delimiter ',' "$REPO_ROOT/testdata/semicolon.csv"
  [ "$status" -eq 0 ]
  [[ "$output" == *"name;score;city"* ]]
  [[ "$output" == *"alice;1234;boston"* ]]
}

@test "renders basic border" {
  run "$TENNIS_BIN" --color=off --border basic --width 80 "$REPO_ROOT/testdata/test.csv"
  [ "$status" -eq 0 ]
  [[ "$output" == *"+-------+---------+------+--------+"* ]]
  [[ "$output" == *"| carat | cut     |"* ]]
  [[ "$output" == *"| 0.230 | Ideal   |"* ]]
}

@test "renders csv from stdin" {
  run bash -lc "cat '$REPO_ROOT/testdata/test.csv' | '$TENNIS_BIN' --color=off --width 80"
  [ "$status" -eq 0 ]
  [[ "$output" == *"carat"* ]]
  [[ "$output" == *"Ideal"* ]]
  [[ "$output" == *"0.31"* ]]
  [[ "$output" == *"344"* ]]
}

@test "renders head rows" {
  run "$TENNIS_BIN" --color=off --width 80 --head 2 "$REPO_ROOT/testdata/test.csv"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Ideal"* ]]
  [[ "$output" == *"Premi"* ]]
  [[ "$output" != *"Very Good"* ]]
}

@test "renders head rows with row numbers" {
  run "$TENNIS_BIN" --color=off --width 80 -n --head 2 "$REPO_ROOT/testdata/test.csv"
  [ "$status" -eq 0 ]
  [[ "$output" == *"│  1 │"* ]]
  [[ "$output" == *"│  2 │"* ]]
  [[ "$output" != *"│  3 │"* ]]
}

@test "renders tail rows with visible row numbers" {
  run "$TENNIS_BIN" --color=off --width 80 -n --tail 2 "$REPO_ROOT/testdata/test.csv"
  [ "$status" -eq 0 ]
  [[ "$output" == *"│  1 │"* ]]
  [[ "$output" == *"│  2 │"* ]]
  [[ "$output" != *"│ 13 │"* ]]
}

@test "sorts rows before head" {
  run "$TENNIS_BIN" --color=off --width 80 --sort name --head 2 "$REPO_ROOT/testdata/test.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"alice"* ]]
  [[ "$output" == *"bob"* ]]
  [[ "$output" != *"cara"* ]]
}

@test "selects and reorders columns" {
  run "$TENNIS_BIN" --color=off --width 80 --select score,name "$REPO_ROOT/testdata/test.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"│ score │ name  │"* ]]
  [[ "$output" != *"city"* ]]
}

@test "deselect removes columns after select" {
  run "$TENNIS_BIN" --color=off --width 80 --select score,name,city --deselect city "$REPO_ROOT/testdata/test.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"│ score │ name  │"* ]]
  [[ "$output" != *"city"* ]]
}

@test "filters rows by case insensitive substring" {
  run "$TENNIS_BIN" --color=off --width 80 --filter ali "$REPO_ROOT/testdata/test.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"alice"* ]]
  [[ "$output" != *"bob"* ]]
  [[ "$output" != *"cara"* ]]
}

@test "renders peek sample and stats" {
  run "$TENNIS_BIN" --color=off --width 80 --peek "$REPO_ROOT/testdata/test.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"3 rows × 5 cols"* ]]
  [[ "$output" == *"alice"* ]]
  [[ "$output" == *"bob"* ]]
  [[ "$output" == *"cara"* ]]
  [[ "$output" == *"│ column │ type"* ]]
  [[ "$output" == *"│ min"* ]]
  [[ "$output" == *"│ max"* ]]
  [[ "$output" == *"│ score  │ int"* ]]
  [[ "$output" == *"│ city   │ string"* ]]
  [[ "$output" == *"│ score  │ int    │ 100% │    3 │ 90"* ]]
  [[ "$output" == *"│ score  │ int    │ 100% │    3 │ 90       │ 5,678"* ]]
  [[ "$output" == *"│ tags   │ string │ 33%  │    1 │ 10 chars │ 10 chars"* ]]
  [[ "$output" == *"│ meta   │ string │ 33%  │    1 │ 11 chars │ 11 chars"* ]]
}

@test "renders peek footer when sample omits rows" {
  run "$TENNIS_BIN" --color=off --width 80 --peek "$REPO_ROOT/testdata/test.csv"
  [ "$status" -eq 0 ]
  [[ "$output" == *"14 rows × 10 cols"* ]]
  [[ "$output" == *"… 9 more rows …"* ]]
  [[ "$output" == *"stats"* ]]
}

@test "reverses rows before head" {
  run "$TENNIS_BIN" --color=off --width 80 --reverse --head 2 "$REPO_ROOT/testdata/test.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"cara"* ]]
  [[ "$output" == *"bob"* ]]
  [[ "$output" != *"alice"* ]]
}

@test "accepts shuffle and shuf aliases" {
  run "$TENNIS_BIN" --color=off --width 80 --shuffle --head 2 "$REPO_ROOT/testdata/test.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"│ name"* ]]

  run "$TENNIS_BIN" --color=off --width 80 --shuf --head 2 "$REPO_ROOT/testdata/test.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"│ name"* ]]
}

@test "renders zebra stripes" {
  run "$TENNIS_BIN" --color=on --theme dark --zebra --width 80 "$REPO_ROOT/testdata/test.csv"
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\e[38;2;255;255;255;48;2;34;34;34m'* ]]
}

@test "sorts naturally with mixed and float columns" {
  run "$TENNIS_BIN" --color=off --vanilla --width 120 --sort mixed --head 1 "$REPO_ROOT/testdata/natsort.csv"
  [ "$status" -eq 0 ]
  [[ "$output" == *"theta"* ]]
  [[ "$output" == *"x02-y2"* ]]

  run "$TENNIS_BIN" --color=off --vanilla --width 120 --sort float --head 1 "$REPO_ROOT/testdata/natsort.csv"
  [ "$status" -eq 0 ]
  [[ "$output" == *"kappa"* ]]
  [[ "$output" == *"0.99"* ]]
}

@test "rejects invalid sort columns without panicking" {
  run "$TENNIS_BIN" --color=off --sort version "$REPO_ROOT/testdata/test.csv"
  [ "$status" -eq 1 ]
  [[ "$output" == *"tennis: --sort didn't look right, should be a comma-separated list of columns."* ]]
  [[ "$output" == *"column names: carat, cut, color, clarity, depth, table, price, x, y, z"* ]]
}

@test "rejects invalid select columns without panicking" {
  run "$TENNIS_BIN" --color=off --select version "$REPO_ROOT/testdata/test.csv"
  [ "$status" -eq 1 ]
  [[ "$output" == *"tennis: --select didn't look right, should be a comma-separated list of columns."* ]]
  [[ "$output" == *"column names: carat, cut, color, clarity, depth, table, price, x, y, z"* ]]
}

@test "rejects invalid deselect columns without panicking" {
  run "$TENNIS_BIN" --color=off --deselect version "$REPO_ROOT/testdata/test.csv"
  [ "$status" -eq 1 ]
  [[ "$output" == *"tennis: --deselect didn't look right, should be a comma-separated list of columns."* ]]
  [[ "$output" == *"column names: carat, cut, color, clarity, depth, table, price, x, y, z"* ]]
}

@test "rejects head and tail together" {
  run "$TENNIS_BIN" --head 2 --tail 2 "$REPO_ROOT/testdata/test.csv"
  [ "$status" -eq 1 ]
  [[ "$output" == *"tennis: Use --head or --tail, not both"* ]]
}

@test "rejects zero head and tail" {
  run "$TENNIS_BIN" --head 0 "$REPO_ROOT/testdata/test.csv"
  [ "$status" -eq 1 ]
  [[ "$output" == *"tennis: Head must be greater than 0"* ]]

  run "$TENNIS_BIN" --tail 0 "$REPO_ROOT/testdata/test.csv"
  [ "$status" -eq 1 ]
  [[ "$output" == *"tennis: Tail must be greater than 0"* ]]
}

@test "renders row numbers" {
  run "$TENNIS_BIN" --color=off --width 80 -n "$REPO_ROOT/testdata/test.csv"
  [ "$status" -eq 0 ]
  [[ "$output" == *"│ #  │"* ]]
  [[ "$output" == *"│  1 │ 0.2… │"* ]]
  [[ "$output" == *"│ 14 │ 0.3… │"* ]]
}

@test "renders unicode csv" {
  run "$TENNIS_BIN" --color=off --width 40 "$REPO_ROOT/testdata/unicode.csv"
  [ "$status" -eq 0 ]
  [[ "$output" == *"│ accent    │ café noir"* ]]
  [[ "$output" == *"│ heart     │ I ❤️ Zig"* ]]
  [[ "$output" == *"│ skin_tone │ thumbs  …"* ]]
  [[ "$output" == *"│ family    │ family  …"* ]]
  [[ "$output" == *"│ flag      │ go 🇺🇸 now"* ]]
}

@test "renders formatted floats and ints" {
  run "$TENNIS_BIN" --color=off --width 120 -n "$REPO_ROOT/testdata/test.csv"
  [ "$status" -eq 0 ]
  [[ "$output" == *"│  1 │ 0.230 │"* ]]
  [[ "$output" == *"│  1 │ 0.230 │ Ideal"* ]]
  [[ "$output" == *"│  1 │ 0.230 │ Ideal     │ E     │ SI2     │ 61.500 │    55 │   326 │"* ]]
}

@test "respects digits option" {
  run "$TENNIS_BIN" --color=off --width 80 --digits 1 "$REPO_ROOT/testdata/test.csv"
  [ "$status" -eq 0 ]
  [[ "$output" == *"0.2"* ]]
  [[ "$output" != *"0.230"* ]]
}

@test "respects vanilla option" {
  run "$TENNIS_BIN" --color=off --width 120 --vanilla "$REPO_ROOT/testdata/test.csv"
  [ "$status" -eq 0 ]
  [[ "$output" == *"0.23"* ]]
  [[ "$output" != *"0.230"* ]]
}

@test "respects theme option" {
  run "$TENNIS_BIN" --color=on --theme dark --width 80 --title foo "$REPO_ROOT/testdata/test.csv"
  [ "$status" -eq 0 ]
  dark="$output"

  run "$TENNIS_BIN" --color=on --theme light --width 80 --title foo "$REPO_ROOT/testdata/test.csv"
  [ "$status" -eq 0 ]
  light="$output"

  [ "$dark" != "$light" ]
}

@test "renders a title" {
  run "$TENNIS_BIN" --color=off --width 80 --title foo "$REPO_ROOT/testdata/test.csv"
  [ "$status" -eq 0 ]
  [[ "$output" == *"foo"* ]]
  [[ "$output" == *"carat"* ]]
  [[ "$output" == *"Premium"* ]]
}

@test "peek respects filter and select" {
  run "$TENNIS_BIN" --color=off --width 120 --peek --filter bob --select name,score "$REPO_ROOT/testdata/test.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"bob"* ]]
  [[ "$output" != *"alice"* ]]
  [[ "$output" == *"│ column │ type"* ]]
  [[ "$output" == *"│ name   │ string │ 100% │    1"* ]]
  [[ "$output" == *"│ score  │ int    │ 100% │    1"* ]]
  [[ "$output" != *"city"* ]]
}

@test "renders basic snapshot" {
  run "$TENNIS_BIN" --color=off --width 80 --title foo "$REPO_ROOT/testdata/test.csv"
  [ "$status" -eq 0 ]
  expected="$(cat "$REPO_ROOT/testdata/basic.out")"
  [ "$output" = "$expected" ]
}

@test "renders basic color snapshot" {
  run "$TENNIS_BIN" --color=on --width 80 --title foo "$REPO_ROOT/testdata/test.csv"
  [ "$status" -eq 0 ]
  expected="$(printf '%b' "$(cat "$REPO_ROOT/testdata/basic-color.out")")"
  [ "$output" = "$expected" ]
}

@test "exits cleanly on short downstream pipe" {
  run bash -o pipefail -lc "'$TENNIS_BIN' --color=off --width 80 '$REPO_ROOT/testdata/test.csv' | sh -c 'exit 0'"
  [ "$status" -eq 0 ]
}
