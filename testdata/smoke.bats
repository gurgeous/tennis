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

@test "rejects extra file arguments" {
  run "$TENNIS_BIN" "$REPO_ROOT/testdata/test.csv" bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"tennis: Too many file arguments"* ]]
}

@test "prints help text" {
  run "$TENNIS_BIN" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: tennis [options] <FILE>"* ]]
  [[ "$output" == *"--color <COLOR>"* ]]
  [[ "$output" == *"--version                   Show version number"* ]]
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

@test "renders csv from stdin" {
  run bash -lc "cat '$REPO_ROOT/testdata/test.csv' | '$TENNIS_BIN' --color=off --width 80"
  [ "$status" -eq 0 ]
  [[ "$output" == *"carat"* ]]
  [[ "$output" == *"Ideal"* ]]
  [[ "$output" == *"0.31"* ]]
  [[ "$output" == *"344"* ]]
}

@test "renders row numbers" {
  run "$TENNIS_BIN" --color=off --width 80 -n "$REPO_ROOT/testdata/test.csv"
  [ "$status" -eq 0 ]
  [[ "$output" == *"│ #  │"* ]]
  [[ "$output" == *"│ 1  │ 0.23"* ]]
  [[ "$output" == *"│ 14 │ 0.31"* ]]
}

@test "renders a title" {
  run "$TENNIS_BIN" --color=off --width 80 --title foo "$REPO_ROOT/testdata/test.csv"
  [ "$status" -eq 0 ]
  [[ "$output" == *"foo"* ]]
  [[ "$output" == *"carat"* ]]
  [[ "$output" == *"Premium"* ]]
}
