export LC_ALL := "en_US.UTF-8"

default:
  just --list

archive target asset:
  rustup target add {{target}}
  just build --release --target {{target}}
  just banner "archive {{target}} {{asset}}..."
  bin/archive {{target}} {{asset}}

build *ARGS:
  just banner "build {{ARGS}}..."
  cargo build --quiet -p tennis-cli {{ARGS}}

build-release: (build "--release")
  ls -lh target/release/tennis

build-small: (build "--profile small")
  ls -lh target/small/tennis

clean:
  cargo clean
  rm -rf tmp && mkdir tmp

gen:
  just banner "gen..."
  just run --completion bash > extra/tennis.bash
  just run --completion zsh > extra/_tennis
  scdoc < extra/tennis.scd > extra/tennis.1
  just banner "✓ gen ✓"

run *ARGS:
  cargo run -p tennis-cli -- {{ARGS}}

#
# check/llm
#

[windows]
check: build test (bats "--filter-tags" "!skipwin")
  just banner "✓ check ✓"

[unix]
check: build lint test bats
  just banner "✓ check ✓"

llm:
  LLM=1 just fmt check

bats *ARGS:
  just banner "bats..."
  if [ -n "${LLM:-}" ]; then \
    bats {{ARGS}} tests/smoke.bats > tmp/bats.out 2>&1 || { cat tmp/bats.out; exit 1; } ; \
  else \
    bats {{ARGS}} --print-output-on-failure tests/smoke.bats ; \
  fi

fmt:
  just banner "fmt..."
  cargo +nightly fmt --all

install: build
  cp target/debug/tennis ~/.local/bin/tennis
  just banner "installed ~/.local/bin/tennis"

lint:
  just banner "lint..."
  rustup --quiet component add --toolchain nightly rustfmt
  rustup --quiet component add clippy
  cargo +nightly fmt --all --check
  cargo clippy --quiet --workspace --all-targets --all-features -- -D warnings

test *ARGS:
  just banner "test {{ARGS}}..."
  cargo test --quiet --workspace --lib --bins {{ARGS}}

test-verbose *ARGS:
  TENNIS_VERBOSE=1 just test {{ARGS}} -- --nocapture

#
# lib
#

build-lib *ARGS:
  just banner "build-lib {{ARGS}}..."
  cargo build --quiet -p tennis {{ARGS}}

test-lib *ARGS:
  just banner "test-lib {{ARGS}}..."
  cargo test --quiet -p tennis --lib {{ARGS}}

#
# dev
#

coverage:
  rm -rf tmp/coverage && mkdir -p tmp/coverage
  mise x cargo:cargo-llvm-cov -- \
    cargo llvm-cov --all-targets --all-features --workspace --html --output-dir tmp/coverage
  just banner "✓ coverage -> tmp/coverage/html/index.html ✓"

callgrind *ARGS: (build "--release --config profile.release.debug=1")
  bin/gen-bench 50000
  valgrind --tool=callgrind --callgrind-out-file=tmp/callgrind.out \
    target/release/tennis --color=on --width 120 {{ARGS}} tmp/bench.csv > /dev/null
  callgrind_annotate --auto=no --threshold=75 tmp/callgrind.out

derive:
  just banner "derive..."
  cargo run --quiet -p tennis --example derive

instrument: build-release
  just banner "gen-bench..."
  gen-bench 1000000 # 1M is good for instrumentation, which runs once
  just banner "instrument..."
  TENNIS_VERBOSE=1 ./target/release/tennis --color=on tmp/bench.csv > /dev/null

man: gen
  man -l extra/tennis.1

readme:
  glow --pager README.md

test-watch:
  NO_COLOR=1 watchexec --clear=clear --stop-timeout=0 just test

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
