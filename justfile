default:
  @just --list

init:
  @# note: golangci-lint has a zed extension, but requires install
  brew install go golangci-lint
  @# note: zed installs gopls
  @# go install golang.org/x/tools/gopls@latest

build *ARGS:
  @go build -o tennis ./cmd

build-release:
  @just build -ldflags=\"-s -w\"

run *ARGS: build
  ./tennis {{ARGS}}

tidy:
  go mod tidy

# don't use this
evil-deep-clean:
  sudo rm -rf ~/.go ~/.local/share/go ~/Library/Caches/golangci-lint

banner +ARGS: (_banner BG_GREEN ARGS)
warning +ARGS: (_banner BG_YELLOW ARGS)
fatal +ARGS: (_banner BG_RED ARGS)
  @exit 1

_banner BG +ARGS:
  @printf '{{BOLD+BG+WHITE}}[%s] %-72s {{NORMAL}}\n' "$(date +%H:%M:%S)" "{{ARGS}}"
