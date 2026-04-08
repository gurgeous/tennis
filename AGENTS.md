## Project

- Small Zig CLI for rendering CSV as terminal tables.

## Important

- Branch names: `^[a-z_]+$`
- COMMIT: include all current changes by default
- PR bodies: 1-2 bullets max, use --body-file, no backticks
- PR: include `Fixes #N` when applicable
- CHANGELOG: match style, reference issues, credit issue authors

## Zig Style

- Use `util.stdout` and `util.stderr` for shared buffered output.
- Never return slices into stack buffers.
- Allocate any string that must outlive the current scope.
- In `src/*.zig`, add a one-line comment to each struct and function.
- Keep imports sorted at the bottom of each file.

## Tests

- Prefer `just llm`. Run `just check` before commits and after larger refactors.
- Keep tests deterministic. Force `--width 80` where layout matters.
- Prefer table-driven tests and tiny helpers in `test_support`, reduce repetition.
- This is partly for token reduction, collapse if clarity stays good
- In `src/*.zig`, if a file has tests, add:
  `//`
  `// testing`
  `//`

## Style

- Keep files and APIs small and direct.
- Prefer simple value types and explicit ownership.
- With `gh pr create`, never use unescaped backticks; prefer `--body-file`.
