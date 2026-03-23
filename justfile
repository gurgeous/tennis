# Required for codex shell sessions where mise PATH hooks may not be active.
export PATH := env("HOME") + "/.local/share/mise/installs/zig/0.15.2/bin:" + env("PATH")

default:
  just --list

build:
  zig build -Doptimize=Debug

build-release:
  zig build -Doptimize=ReleaseSmall

clean:
  rm -rf tmp zig-out

run *ARGS:
  zig build run -- {{ARGS}}

#
# hygiene
#

check: clean-weekly build lint test bats
  just banner "✓ check ✓"

llm: fmt
  LLM=1 just check

bats: build
  if [ -n "${LLM:-}" ]; then bats testdata/smoke.bats > /dev/null ; else bats testdata/smoke.bats ; fi
  just banner "✓ bats ✓"

ci: check
  just banner "✓ ci ✓"

clean-weekly:
  if [ -d tmp ] && [ "$(find tmp -type d -prune -mtime +7 | wc -l)" -gt 0 ]; then \
    just clean ; \
    just banner "✓ clean-weekly ✓" ; \
  fi

fmt:
  zig fmt src build.zig
  just banner "✓ fmt ✓"

lint:
  zig fmt --check src build.zig
  bin/lint-args
  bin/lint-imports
  just banner "✓ lint ✓"

test:
  if [ -n "${LLM:-}" ]; then zig build test --summary none ; else zig build test --summary all ; fi
  just banner "✓ test ✓"

test-watch:
  watchexec --clear=clear --stop-timeout=0 just test

#
# benchmark
# Be sure to use build-release here. We intentionally benchmark `ReleaseSmall`
# because binary size matters more than peak throughput for this app. On the
# current tree, `ReleaseFast` was ~25x larger (3.4 MB vs 136 KB), ~2x faster on
# csv, and only ~16% faster on json.
#

benchmark:
  just benchmark-csv
  just benchmark-json
  just benchmark-jsonl
  just banner "✓ benchmark ✓"

benchmark-csv: build-release
  bin/gen-benchmark-csv > tmp/tennis-benchmark.csv
  BENCHMARK=1 ./zig-out/bin/tennis --color=on --width 80 tmp/tennis-benchmark.csv > /dev/null
  just banner "✓ benchmark-csv ✓"

benchmark-json: build-release
  bin/gen-benchmark-json > tmp/tennis-benchmark.json
  BENCHMARK=1 ./zig-out/bin/tennis --color=on --width 80 tmp/tennis-benchmark.json > /dev/null
  just banner "✓ benchmark-json ✓"

benchmark-jsonl: build-release
  bin/gen-benchmark-json | sed '1d;$d;s/,$//' > tmp/tennis-benchmark.jsonl
  BENCHMARK=1 ./zig-out/bin/tennis --color=on --width 80 tmp/tennis-benchmark.jsonl > /dev/null
  just banner "✓ benchmark-jsonl ✓"

#
# release and related items
#

completions: build
  just run --completion bash > extra/tennis.bash
  just run --completion zsh > extra/_tennis
  just banner "completion diffs, if any..."
  git --no-pager diff -- extra/tennis.bash extra/_tennis
  just banner "✓ completions ✓"

man:
  scdoc < extra/tennis.scd > extra/tennis.1
  man -l extra/tennis.1

readme:
  glow --pager README.md

release-preview: check
  goreleaser release --clean --snapshot
  just banner "macOS tarball preview..."
  tar -tvzf "$(find tmp/dist -maxdepth 1 -name 'tennis_*_darwin_arm64.tar.gz' | head -n 1)"

release: check valgrind
  bin/release

[working-directory: 'tmp']
screenshot: build
  ../bin/screenshot
  just banner "✓ screenshot - see tmp/vhs.png ✓"

#
# more esoteric hygiene
#

kcov:
  just banner "kcov..."
  rm -rf tmp/kcov
  zig build  -Doptimize=Debug kcov-tests
  kcov --include-pattern=$PWD/src/ --exclude-line=errdefer tmp/kcov ./zig-out/bin/kcov-tests
  just banner "✓ kcov ✓"

valgrind: build
  valgrind --quiet --leak-check=full --show-leak-kinds=all --errors-for-leak-kinds=all --error-exitcode=1 \
    ./zig-out/bin/tennis  --color=on -n --title foo testdata/test.csv > /dev/null
  just banner "✓ valgrind ✓"

#
# banner
#

set quiet

banner +ARGS:  (_banner '\e[48;2;064;160;043m' ARGS)
warning +ARGS: (_banner '\e[48;2;251;100;011m' ARGS)
fatal +ARGS:   (_banner '\e[48;2;210;015;057m' ARGS)
  exit 1
_banner BG +ARGS:
  if [ -z "${LLM:-}" ]; then \
    printf '\e[38;5;231m{{BOLD+BG}}[%s] %-72s {{NORMAL}}\n' "$(date +%H:%M:%S)" "{{ARGS}}" ; \
  fi
