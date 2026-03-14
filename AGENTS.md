# AGENTS

## Project Shape

- Small Zig CLI for rendering CSV as terminal tables.
- Keep modules focused: `args` parses CLI, `main` owns process flow, `render` owns output behavior, `util` holds shared helpers.
- Prefer simple value types and explicit ownership over clever abstractions.

## CLI Conventions

- `Args.init(alloc, argv)` parses arguments and returns structured control flow.
- Use `Action` for early exits: `banner`, `fatal`, `help`, `version`.
- Fatal CLI/setup errors should return owned `err_str` text; `main` prints and decides exit code.

## I/O Conventions

- Use `/dev/tty` for terminal-only probing (`termWidth`, terminal background detection).
- Do not mix terminal probing with stdin CSV input.
- `util.stdout` and `util.stderr` are the shared buffered writers.

## Memory Rules

- No arena allocator in the main app path; free what you allocate.
- Never return slices into local stack buffers.
- If a string must outlive the current scope, allocate it (`allocPrint`, `dupe`).
- `util.readCsv` returns owned rows/fields; callers must `util.freeCsv`.

## Testing

- Keep `just check` green: lint, unit tests, snapshot smoke tests.
- Run `just check` after every code change.
- Use snapshot tests for CLI output and regressions in user-facing errors.
- Keep tests deterministic by forcing `--width 80` where layout matters.
- Use `just kcov` for coverage work.
- Read `kcov/.../coverage.json` for machine-readable coverage results.

## Style

- Keep files and APIs small and direct.
- Prefer straightforward Zig control flow (`switch`, `try`, explicit cleanup).
- Keep imports sorted at the bottom of each file.
