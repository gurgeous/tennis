# Required for codex shell sessions where mise PATH hooks may not be active.
export PATH := env("HOME") + "/.local/share/mise/installs/zig/0.15.2/bin:" + env("PATH")

default:
  just --list

build:
  zig build -Doptimize=Debug

build-release:
  zig build -Doptimize=ReleaseSmall

clean:
    rm -rf .zig-cache zig-out

run *ARGS:
  zig build run -- {{ARGS}}

#
# hygiene
#

check: lint build test test-snaps
  just banner "✓ check ✓"

fmt:
  zig fmt .
  just banner "✓ fmt ✓"


lint:
  zig fmt --check .
  just banner "✓ lint ✓"

test:
  zig build test
  just banner "✓ test ✓"

test-snaps: build
  ./bin/snap.sh testdata/smoke-bad-arg.txt     ./zig-out/bin/tennis --bogus
  ./bin/snap.sh testdata/smoke-error.txt       ./zig-out/bin/tennis testdata/test.csv bogus
  ./bin/snap.sh testdata/smoke-help.txt        ./zig-out/bin/tennis --help
  ./bin/snap.sh testdata/smoke-invalid-csv.txt  sh -c 'printf "a,b\n\"oops\n" | ./zig-out/bin/tennis --color=never'
  ./bin/snap.sh testdata/smoke-jagged.txt       sh -c 'printf "a,b\nc\n" | ./zig-out/bin/tennis --color=never'
  ./bin/snap.sh testdata/smoke-pipe.txt         sh -c 'cat testdata/test.csv | ./zig-out/bin/tennis --color=never --width 80'
  ./bin/snap.sh testdata/smoke-rows.txt         ./zig-out/bin/tennis --color=never --width 80 -n testdata/test.csv
  ./bin/snap.sh testdata/smoke-title.txt        ./zig-out/bin/tennis --color=never --width 80 --title foo testdata/test.csv
  just banner "✓ test-snaps ✓"

gen-snaps:
  GEN=1 just test-snaps

valgrind: build
  valgrind --quiet --leak-check=full --show-leak-kinds=all --errors-for-leak-kinds=all --error-exitcode=1 \
    ./zig-out/bin/tennis  --color=always -n --title foo testdata/test.csv > /dev/null
  just banner "✓ valgrind ✓"

#
# banner
#

set quiet := true

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
