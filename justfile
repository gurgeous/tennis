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
# goreleaser
# git tag -a v0.1.0 -m "First release" && git push origin v0.1.0
# git push --delete origin v0.1.0 && git tag -d v0.1.0
#

goreleaser *ARGS: check
  just banner "goreleaser release..."
  goreleaser healthcheck
  if [ -z "${GITHUB_TOKEN:-}" ]; then just fatal "GITHUB_TOKEN is required" ; fi
  goreleaser release --clean {{ARGS}}
  just banner "✓ goreleaser ✓"

goreleaser-preview *ARGS:
  goreleaser healthcheck
  goreleaser release --clean --skip=publish {{ARGS}}

goreleaser-snapshot: check
  goreleaser release --snapshot --clean
  just banner "✓ goreleaser-snapshot ✓"

#
# check and friends
#

check: lint build test bats
  just banner "✓ check ✓"

bats: build
  bats testdata/smoke.bats
  just banner "✓ bats ✓"

ci: check
  just banner "✓ ci ✓"

fmt:
  zig fmt .
  just banner "✓ fmt ✓"

lint:
  zig fmt --check .
  just banner "✓ lint ✓"

test:
  zig build test --summary all
  just banner "✓ test ✓"

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
