# Repository Guidelines

## Project Structure & Module Organization

- `cmd/` holds the CLI entrypoint and options (`tennis.go`, `options.go`).
- Root-level `*.go` files contain the core rendering, layout, table, and styling logic.
- Tests live alongside code as `*_test.go`
- `test.csv` is a sample input for local runs and snapshot tests.
- Generated artifacts include `*_string.go` (via `go generate`) and the built `tennis` binary.

## Build, Test, and Development Commands

Use `just` for common workflows (see `justfile`). Don't attempt to run `go` or `gofmt` directly. Always run `AGENT=1 just check` after changes. Here are the main commands:

- `just build` — compile the CLI to `./tennis`.
- `AGENT=1 just check` — build + lint + tests (AGENT=1 skips `testdata/5.txt` in snapshot tests)
- `just gen` — run `go generate` and `go mod tidy`.

## Coding Style & Naming Conventions

- Go standard formatting is expected; Uses `golangci-lint`.
- Keep identifiers ASCII-safe
- Prefer short names; exported items use Go’s `CamelCase`, locals use `camelCase`.

## Testing Guidelines

- Tests use Go’s built-in `testing` package with `testify` helpers.
- Name tests `TestXxx` in `*_test.go`
- Only regenerate snapshots via `GEN=1 just test-snaps` when explicitly requested.

## Commit & Pull Request Guidelines

- Use short, descriptive, imperative commits (e.g., `Add snapshot for color output`).
- PRs should include: a brief summary, linked issues (if any), and before/after sample CLI output if helpful
