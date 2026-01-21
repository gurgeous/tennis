
default:
  @just --list

init:
  @# note: golangci-lint has a zed extension, but requires install
  brew install go golangci-lint
  go install golang.org/x/tools/cmd/stringer@latest
  @# note: zed installs gopls
  @# go install golang.org/x/tools/gopls@latest

# REMIND: sha, version, etc
# see ~/sync/vectrogo/justfile for goreleaser
build *ARGS:
  @just banner build...
  go generate
  go build -o tennis {{ARGS}} ./cmd
  @ls -lh tennis

build-release:
  @just build -ldflags=\"-s -w\"


#
# dev
#

kong: build
  @clear
  @just banner  "kong: no args"  ; ./tennis
  @just banner  "kong: --help"   ; ./tennis --help
  @just banner  "kong: w/file"   ; ./tennis test.csv
  @just banner  "kong: stdin -"  ; cat test.csv | ./tennis -
  @just banner  "kong: stdin"    ; cat test.csv | ./tennis
  @just warning "kong: bad file" ; ./tennis bogus || true
  @just warning "kong: missing"  ; ./tennis -n || true
  @just banner Done

lint *ARGS:
  golangci-lint run {{ARGS}}

run *ARGS:
  @go run ./... {{ARGS}}

test *ARGS:
  @go test ./... {{ARGS}}

tidy:
  go mod tidy

#
# banner
#

banner +ARGS: (_banner BG_GREEN ARGS)
warning +ARGS: (_banner BG_YELLOW ARGS)
fatal +ARGS: (_banner BG_RED ARGS)
  @exit 1

_banner BG +ARGS:
  @printf '{{BOLD+BG+WHITE}}[%s] %-72s {{NORMAL}}\n' "$(date +%H:%M:%S)" "{{ARGS}}"
