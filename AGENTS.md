## Project

- A small CLI for rendering CSV/JSON/SQLite data as terminal tables.

## Important

- Branch names: `^[a-z_]+$`
- COMMIT: include all current changes by default.
- PR bodies: 1-2 bullets max, use `--body-file`, no backticks.
- PR merge: do not wait for CI unless asked.
- PR: include `Fixes #N` when applicable.
- CHANGELOG: match style, reference issues, credit issue authors.

## Rust Style

- Use idiomatic Rust: `rustfmt`, `clippy`, `Result`, clear ownership, small modules.
- Keep APIs small; avoid one-use wrappers unless they clarify behavior.
- Treat long arg lists as a smell; options structs must model real domain values.
- Avoid test-only dependency injection; prefer real value objects or direct code.
- Comment any API split that exists only for tests or other non-primary paths.
- Prefer table-driven tests and tiny helpers over repeated setup.
- Name Rust unit tests `test_fn_name`; use `test_fn_name_case` only when one function needs multiple tests.
- Explain intent, jargon, or tradeoffs; skip name/type restatements.
- Preserve helpful explanatory comments when moving or refactoring code.
- Keep file headers under five words unless documenting an invariant or algorithm.
- Comment structs/enums/fields only for intent, invariants, jargon, or non-obvious behavior.
- Do not remove comments without asking. Preserve comments during refactors. Don't add stupid comments.
- Be especially hesitant to remove section comments; they are often reader aids even when they look redundant.
- Import sibling modules/items at top; avoid repeated inline `crate::foo::bar`.
- Use Rust doc comments idiomatically: `//!` for module docs and `///` for public API docs.
- Do not map our own errors except at real layer boundaries; add context at the source.
- Silently ignore non-actionable stdout/pager write failures.
- Keep crate-sensitive behavior behind local modules: `natord`, `unicode-width`, `termbg`.

## Tests

- Use `just` tasks. Do not run `cargo fmt` directly; `just llm` uses nightly rustfmt.
- After each code change, run `just llm`.
- Keep tests deterministic. Force `--width 80` where layout matters.
- Never probe terminal theme/background in tests; always skip it when color is off.
- Do not force flags in every parity test; cover defaults explicitly.
- Every old runtime/system probe needs a Rust equivalent and test.

## Style

- Keep files/APIs small and direct.
- Prefer `cell` over `field` in code and comments.
- Bin scripts and important files should start with a short top-level comment.
- Prefer simple values and explicit ownership.
