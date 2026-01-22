package main

import (
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestMain0(t *testing.T) {
	// try something real basic/
	const input = `
a,b
c,d
`

	const exp = `
╭────┬────╮
│ a  │ b  │
├────┼────┤
│ c  │ d  │
╰────┴────╯
`

	_, stdout := captureMain(t, []string{"--color=never"}, strings.TrimSpace(input))
	assert.Equal(t, strings.TrimSpace(exp), strings.TrimSpace(stdout))
}

func captureMain(t *testing.T, args []string, stdin string) (exit int, stdout string) {
	// mock exit
	exit = didntExit
	exitFn := func(code int) { exit = code }
	// go
	_, stdout = capture(t, args, stdin, func() bool { return main0(exitFn) })
	return
}
