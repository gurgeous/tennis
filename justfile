
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
  @just banner test-snaps ; just test-snaps
  @just banner done

lint *ARGS:
  golangci-lint run {{ARGS}}

run *ARGS:
  @go run ./... {{ARGS}}

# $ go help testflag
# $ go tool cover -help
# use -v to see stdout
test *ARGS:
  @go test ./... {{ARGS}}

test-cover:
  @clear
  @just banner "Running tests..."
  @go test ./... -coverprofile /tmp/cover.out
  @just banner "Coverage report..."
  @go tool cover -func /tmp/cover.out | rg -v "\w+_string.go"

test-watch *ARGS:
  @watchexec --watch . --clear=reset just test "{{ARGS}}"

# simple snapshot testing
test-snaps:
  @./snap.sh testdata/0.txt ./tennis --color=always test.csv -n
  @./snap.sh testdata/1.txt ./tennis --color=always test.csv --title foo
  @./snap.sh testdata/2.txt ./tennis test.csv
  @./snap.sh testdata/3.txt sh -c 'cat test.csv | ./tennis'
  @./snap.sh testdata/4.txt sh -c 'cat test.csv | ./tennis -'
  @./snap.sh testdata/5.txt ./tennis
  @./snap.sh testdata/6.txt ./tennis test.csv bogus

#
# gen
#

gen:
  go generate
  go mod tidy

gen-snaps:
  @clear
  @rm -rf testdata/ && mkdir -p testdata/
  @GEN=1 just test-snaps ; echo ; cat testdata/*
  @just banner update-snaps done

#
# banner
#

banner +ARGS: (_banner BG_GREEN ARGS)
warning +ARGS: (_banner BG_YELLOW ARGS)
fatal +ARGS: (_banner BG_RED ARGS)
  @exit 1
_banner BG +ARGS:
  @printf '{{BOLD+BG+WHITE}}[%s] %-72s {{NORMAL}}\n' "$(date +%H:%M:%S)" "{{ARGS}}"
