
default:
  @just --list

init:
  brew install go golangci-lint
  go install golang.org/x/tools/cmd/stringer@latest

build *ARGS:
  @go build -o tennis {{ARGS}} ./cmd

build-release:
  @just build -ldflags=\"-s -w\"

#
# dev
#

check:
  @just banner build ; just build
  @just banner lint ; just lint
  @just banner test ; just test
  @just banner test-snap ; just test-snap
  @just banner done

lint *ARGS:
  golangci-lint run {{ARGS}}

refresh:
  go generate
  go mod tidy

run *ARGS:
  @go run ./... {{ARGS}}

# use -v to see stdout
test *ARGS:
  @go test ./... {{ARGS}}

test-watch *ARGS:
  @watchexec --watch . --clear=reset just test "{{ARGS}}"

# simple snapshot testing
test-snap:
  @./snap.sh snaps/0.txt ./tennis test.csv
  @./snap.sh snaps/1.txt ./tennis
  @./snap.sh snaps/2.txt ./tennis --help
  @./snap.sh snaps/3.txt ./tennis test.csv -n
  @./snap.sh snaps/4.txt ./tennis test.csv bogus
  @./snap.sh snaps/5.txt sh -c 'cat test.csv | ./tennis'
  @./snap.sh snaps/6.txt sh -c 'cat test.csv | ./tennis -'

#
# banner
#

banner +ARGS: (_banner BG_GREEN ARGS)
warning +ARGS: (_banner BG_YELLOW ARGS)
fatal +ARGS: (_banner BG_RED ARGS)
  @exit 1
_banner BG +ARGS:
  @printf '{{BOLD+BG+WHITE}}[%s] %-72s {{NORMAL}}\n' "$(date +%H:%M:%S)" "{{ARGS}}"
