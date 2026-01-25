# set quiet (someday)

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
  go install golang.org/x/tools/cmd/stringer@latest

#
# dev
#

@build *ARGS:
  go build -o tennis {{ARGS}} ./cmd

@check:
  just banner build ; just build
  just banner lint ; just lint
  if [ -n "${CODEX_SANDBOX_NETWORK_DISABLED-}" ]; then \
    just warning "skip test-snaps under Codex"; \
  else \
    just banner test-snaps ; just test-snaps; \
  fi
  just banner test ; just test
  just banner done

[working-directory: 'docs']
vhs:
  @clear ; just banner "vhs..."
  @rm -f /tmp/demo.{gif,png} demo.png
  vhs demo.tape
  pngquant --skip-if-larger --quality 80 --strip --output demo.png /tmp/demo.png
  qlmanage -p demo.png

@lint *ARGS:
  golangci-lint run {{ARGS}}

@run *ARGS:
  go run ./... {{ARGS}}

# $ go help testflag
# $ go tool cover -help
# use -v to see stdout
@test *ARGS:
  go test ./... {{ARGS}}

@test-cover:
  clear ; banner "Running tests..."
  go test ./... -coverprofile /tmp/cover.out
  just banner "Coverage report..."
  go tool cover -func /tmp/cover.out | rg -v "\w+_string.go"

# $ just test-watch -run regex
@test-watch *ARGS:
  watchexec --watch . --clear=reset just test "{{ARGS}}"

# simple snapshot testing
@test-snaps: build
  ./bin/snap.sh testdata/0.txt ./tennis --color=always testdata/test.csv -n
  ./bin/snap.sh testdata/1.txt ./tennis --color=always testdata/test.csv --title foo
  ./bin/snap.sh testdata/2.txt ./tennis testdata/test.csv
  ./bin/snap.sh testdata/3.txt sh -c 'cat testdata/test.csv | ./tennis'
  ./bin/snap.sh testdata/4.txt sh -c 'cat testdata/test.csv | ./tennis -'
  ./bin/snap.sh testdata/5.txt ./tennis
  ./bin/snap.sh testdata/6.txt ./tennis testdata/test.csv bogus

#
# gen
#

gen:
  go generate
  go mod tidy

@gen-snaps:
  clear
  rm -rf testdata/*.txt
  GEN=1 just test-snaps ; echo ; cat testdata/*.txt
  just banner update-snaps done

#
# release
# https://goreleaser.com/quick-start/#live-examples

@release:
  clear ; just banner "just check..." ; just check
  just banner "goreleaser release..."
  if [ -z "${GITHUB_TOKEN:-}" ]; then just _fatal "GITHUB_TOKEN is required" ; fi
  goreleaser release --clean
  just banner "done"

@snapshot:
  clear ; just banner "just check..." ; just check
  just banner "goreleaser --snapshot..."
  goreleaser release --snapshot --clean
  just banner "done"

#
# banner
#

[private]
banner +ARGS: (_banner BG_GREEN ARGS)
[private]
warning +ARGS: (_banner BG_YELLOW ARGS)
[private]
@fatal +ARGS: (_banner BG_RED ARGS)
  exit 1
@_banner BG +ARGS:
  printf '{{BOLD+BG+WHITE}}[%s] %-72s {{NORMAL}}\n' "$(date +%H:%M:%S)" "{{ARGS}}"
