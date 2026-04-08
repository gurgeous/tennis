# AGENTS

## Project

- Small Zig CLI for rendering CSV as terminal tables.
- Keep modules narrow: `args` parses CLI, `main` owns process flow, `render` owns output, `util` holds shared helpers.
- Prefer simple value types and explicit ownership.

## CLI

- `Args.init(alloc, argv)` returns structured control flow.
- Use `Action` for early exits: `banner`, `fatal`, `help`, `version`.
- Fatal CLI/setup errors should return owned `err_str`; `main` prints and picks the exit code.

## I/O

- Use `/dev/tty` only for terminal probing such as width or background detection.
- Do not mix terminal probing with stdin table input.
- Use `util.stdout` and `util.stderr` for shared buffered output.

## Memory

- Never return slices into stack buffers.
- Allocate any string that must outlive the current scope.

## Tests

- Prefer `just llm`. Run `just check` before commits and after larger refactors.
- Keep tests deterministic. Force `--width 80` where layout matters.
- Prefer table-driven tests and tiny helpers in `test_support` or the local test section when they reduce repetition.
- This is partly for token reduction, colllapse if clarity stays good
- In `src/*.zig`, if a file has tests, add:
  `//`
  `// testing`
  `//`

## Style

- Keep files and APIs small and direct.
- Prefer straightforward Zig control flow.
- In `src/*.zig`, add a one-line comment to each struct and function.
- Keep imports sorted at the bottom of each file.
- Branch names should match `^[a-z_]+$`.
- When the user says `commit`, commit all current changes by default, including unrelated local edits.
- With `gh pr create`, never use unescaped backticks; prefer `--body-file`.
