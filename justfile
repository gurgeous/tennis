# Required for codex shell sessions where mise PATH hooks may not be active.
export PATH := env("HOME") + "/.local/share/mise/installs/zig/0.15.2/bin:" + env("PATH")

default:
  just --list

build:
  zig build -Doptimize=Debug

build-release:
  zig build -Doptimize=ReleaseSmall

clean:
    rm -rf kcov .zig-cache zig-out

run *ARGS:
  zig build run -- {{ARGS}}

#
# benchmark
# Be sure to use the release binary here, debug builds are terrible for
# benchmarking.
#

benchmark: build-release
  bin/gen-benchmark-csv > /tmp/tennis-benchmark.csv
  BENCHMARK=1 ./zig-out/bin/tennis --color=on --width 80 /tmp/tennis-benchmark.csv > /dev/null
  just banner "✓ benchmark ✓"

#
# release
#

release: check valgrind
  bin/release

goreleaser-preview: check
  goreleaser release --clean --snapshot
  just banner "macOS tarball preview..."
  tar -tvzf "$(find dist -maxdepth 1 -name 'tennis_*_darwin_arm64.tar.gz' | head -n 1)"

#
# hygiene
#

check: clean-weekly lint lint-imports build test bats
  just banner "✓ check ✓"


bats: build
  bats testdata/smoke.bats
  just banner "✓ bats ✓"

ci: check
  just banner "✓ ci ✓"

clean-weekly:
  if [ -d .zig-cache ] && [ "$(stat -c %Z .zig-cache)" -lt "$(date -d '7 days ago' +%s)" ]; then \
    just clean ; \
    just banner "✓ clean-weekly ✓" ; \
  fi

completions: build
  just run --completion bash > extra/tennis.bash
  just run --completion zsh > extra/_tennis
  just banner "✓ completions ✓"

fmt:
  zig fmt .
  just banner "✓ fmt ✓"

lint:
  zig fmt --check .
  bash bin/lint-args
  just banner "✓ lint ✓"

lint-imports:
  bash bin/lint-imports
  just banner "✓ lint-imports ✓"

man:
  scdoc < extra/tennis.scd > extra/tennis.1
  man -l extra/tennis.1

readme:
  glow --pager README.md

test:
  zig build test --summary all
  just banner "✓ test ✓"

#
# more esoteric hygiene
#

kcov:
  just banner "kcov..."
  rm -rf kcov/
  zig build  -Doptimize=Debug kcov-tests
  kcov --include-pattern=$PWD/src/ --exclude-line=errdefer kcov ./zig-out/bin/kcov-tests
  just banner "✓ kcov ✓"

valgrind: build
  valgrind --quiet --leak-check=full --show-leak-kinds=all --errors-for-leak-kinds=all --error-exitcode=1 \
    ./zig-out/bin/tennis  --color=on -n --title foo testdata/test.csv > /dev/null
  just banner "✓ valgrind ✓"

#
# banner
#

set quiet

TRUWHITE := '\e[38;5;231m'
GREEN    := '\e[48;2;064;160;043m'
ORANGE   := '\e[48;2;251;100;011m'
RED      := '\e[48;2;210;015;057m'

banner +ARGS: (_banner GREEN ARGS)
warning +ARGS: (_banner ORANGE ARGS)
fatal +ARGS: (_banner RED ARGS)
  exit 1
_banner BG +ARGS:
  printf '{{BOLD+TRUWHITE+BG}}[%s] %-72s {{NORMAL}}\n' "$(date +%H:%M:%S)" "{{ARGS}}"
