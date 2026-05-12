default:
  just --list

build:
  zig build -Doptimize=Debug

build-release:
  zig build -Doptimize=ReleaseSmall

build-windows:
  zig build -Dtarget=x86_64-windows-gnu

clean:
  rm -rf tmp zig-out zig-pkg .zig-cache
  mkdir tmp

install: check build-release
  cp zig-out/bin/tennis ~/.local/bin/tennis

run *ARGS:
  zig build run -- {{ARGS}}

#
# dev
#

[unix]
check: clean-weekly build lint test test-bats
  just banner "✓ check ✓"

[windows]
check: build-windows
  just test-bats --filter-tags '!skipwin'
  just banner "✓ check ✓"

ci: check

clean-weekly:
  if [ -d tmp ] && [ "$(find tmp -type d -prune -mtime +7 | wc -l)" -gt 0 ]; then \
    just clean ; \
  fi

fmt:
  zig fmt src build.zig
  just banner "✓ fmt ✓"

kcov: clean
  just banner "kcov..."
  zig build -Doptimize=Debug kcov-tests
  kcov --include-pattern=$PWD/src/ --exclude-line=errdefer tmp/kcov ./zig-out/bin/kcov-tests
  just banner "see tmp/kcov"

lint:
  zig fmt --check src build.zig
  bin/lint-args
  bin/lint-imports
  just banner "✓ lint ✓"

llm: fmt
  LLM=1 just check

man: gen
  man -l extra/tennis.1

readme:
  glow --pager README.md

test:
  if [ -n "${LLM:-}" ]; then zig build test --summary none ; else zig build test --summary all ; fi
  just banner "✓ test ✓"

test-bats *ARGS:
  if [ -n "${LLM:-}" ]; then \
    bats {{ARGS}} testdata/smoke.bats > /dev/null ; \
  else \
    bats {{ARGS}} --print-output-on-failure testdata/smoke.bats ; \
  fi
  just banner "✓ test-bats ✓"

test-watch:
  watchexec --clear=clear --stop-timeout=0 just test

valgrind: build
  valgrind --quiet --leak-check=full --show-leak-kinds=all --errors-for-leak-kinds=all --error-exitcode=1 \
    ./zig-out/bin/tennis  --color=on -n --title foo testdata/test.csv > /dev/null
  just banner "✓ valgrind ✓"

#
# benchmark - We intentionally benchmark `ReleaseSmall` because bin size matters
# more than peak throughput for this app.
#

benchmark: benchmark-csv benchmark-json

benchmark-csv: build-release
  just banner "benchmark-csv"
  bin/gen-benchmark-csv > tmp/tennis-benchmark.csv
  BENCHMARK=1 ./zig-out/bin/tennis --width 80 tmp/tennis-benchmark.csv > /dev/null

benchmark-json: build-release
  bin/gen-benchmark-json > tmp/tennis-benchmark.json
  cat tmp/tennis-benchmark.json | sed '1d;$d;s/,$//' > tmp/tennis-benchmark.jsonl
  just banner "benchmark-json"
  BENCHMARK=1 ./zig-out/bin/tennis --width 80 tmp/tennis-benchmark.json > /dev/null
  just banner "benchmark-jsonl"
  BENCHMARK=1 ./zig-out/bin/tennis --width 80 tmp/tennis-benchmark.jsonl > /dev/null

#
# release and related items
#

gen:
  just run --completion bash > extra/tennis.bash
  just run --completion zsh > extra/_tennis
  scdoc < extra/tennis.scd > extra/tennis.1
  just banner "✓ gen ✓"

release: check valgrind
  bin/release

release-preview: check
  goreleaser release --clean --snapshot
  just banner "macOS tarball preview..."
  tar -tvzf "$(find tmp/dist -maxdepth 1 -name 'tennis_*_darwin_arm64.tar.gz' | head -n 1)"

[working-directory: 'tmp']
screenshot: build
  ../bin/screenshot
  just banner "✓ screenshot - see tmp/vhs.png ✓"

#
# banner
#

set quiet

banner msg bg="64;160;43":
  if [ -z "${LLM:-}" ]; then \
    printf "\e[1;38;5;231;48;2;%sm[%s] %-72s\e[0m\n" "{{bg}}" $(date +"%H:%M:%S") "{{msg}}" ; \
  fi
warning +msg: (banner msg "251;100;11")
fatal +msg: (banner msg "210;15;57")
  exit 1
