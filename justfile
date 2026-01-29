
default:
  just --list

#
# init
#

[macos]
init: _init-common
  brew install go golangci-lint
  brew install --cask goreleaser/tap/goreleaser
[linux]
init: _init-common
  curl -sSfL https://golangci-lint.run/install.sh | sh -s -- -b $(go env GOPATH)/bin v2.8.0
_init-common:
  go install golang.org/x/tools/cmd/stringerlatest

#
# dev
#

build *ARGS:
  go build -o tennis {{ARGS}} ./cmd

check:
  just banner build ; just build
  just banner lint ; just lint
  just banner test-snaps ; just test-snaps
  just banner test ; just test
  just banner done

lint *ARGS:
  golangci-lint run {{ARGS}}

fmt *ARGS:
  golangci-lint run --fix {{ARGS}}

run *ARGS:
  go run ./... {{ARGS}}

test *ARGS:
  # use -v to see stdout
  go test ./... {{ARGS}}

test-cover:
  clear ; just banner "Running tests..."
  go test ./... -coverprofile /tmp/cover.out
  just banner "Coverage report..."
  go tool cover -func /tmp/cover.out | rg -v "\w+_string.go"

# $ just test-watch -run regex
test-watch *ARGS:
  watchexec --watch . --clear=reset just test "{{ARGS}}"

# simple snapshot testing
test-snaps: build
  ./bin/snap.sh testdata/0.txt ./tennis --color=always -n testdata/test.csv
  ./bin/snap.sh testdata/1.txt ./tennis --color=always --title foo testdata/test.csv
  ./bin/snap.sh testdata/2.txt ./tennis testdata/test.csv
  ./bin/snap.sh testdata/3.txt sh -c 'cat testdata/test.csv | ./tennis'
  ./bin/snap.sh testdata/4.txt sh -c 'cat testdata/test.csv | ./tennis -'
  if [ -z "${AGENT-}" ]; then ./bin/snap.sh testdata/5.txt ./tennis ; fi
  ./bin/snap.sh testdata/6.txt ./tennis testdata/test.csv bogus

[working-directory: 'docs']
vhs:
  clear ; just banner "vhs..."
  rm -f /tmp/demo.{gif,png} demo.png
  vhs demo.tape
  pngquant --skip-if-larger --quality 80 --strip --output demo.png /tmp/demo.png
  qlmanage -p demo.png

#
# gen
#

gen:
  go generate
  go mod tidy

gen-snaps:
  clear
  rm -rf testdata/*.txt
  GEN=1 just test-snaps ; echo ; cat testdata/*.txt
  just banner update-snaps done

#
# release
# https://goreleaser.com/quick-start/#live-examples

release *ARGS:
  # git tag -a v0.1.0 -m "First release" && git push origin v0.1.0
  # git push --delete origin v0.1.0 && git tag -d v0.1.0
  clear ; just banner "just check..." ; just check
  just banner "goreleaser release..."
  goreleaser healthcheck
  if [ -z "${GITHUB_TOKEN:-}" ]; then just _fatal "GITHUB_TOKEN is required" ; fi
  goreleaser release --clean {{ARGS}}
  just banner "done"

release-preview *ARGS:
  goreleaser healthcheck
  goreleaser release --clean --skip=publish {{ARGS}}
  just banner "done"

snapshot:
  clear ; just banner "just check..." ; just check
  just banner "goreleaser --snapshot..."
  goreleaser release --snapshot --clean
  just banner "done"

#
# banner
#

_WHITE  := '\e[38;2;255;255;255m' # white fg
_GREEN  := '\e[48;2;64;160;43m'   # green bg
_YELLOW := '\e[48;2;251;100;11m'  # yellow bg
_RED    := '\e[48;2;210;15;57m'   # red bg

[private]
test-banner:
  just banner  "this is banner"
  just warning "this is warning"
  just fatal   "this is fatal"

[private]
banner +ARGS: (_banner _GREEN ARGS)
[private]
warning +ARGS: (_banner _YELLOW ARGS)
[private]
fatal +ARGS: (_banner _RED ARGS)
  exit 1
_banner COLOR + ARGS:
  printf '{{BOLD+_WHITE+COLOR}}[%s] %-72s {{NORMAL}}\n' "$(date +%H:%M:%S)" "{{ARGS}}"

# turn off echoing
set quiet := true
