package main

import (
	"bytes"
	"io"
	"os"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestMain0(t *testing.T) {
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

	_, stdout := captureMain(t, []string{}, strings.TrimSpace(input))
	assert.Equal(t, strings.TrimSpace(exp), strings.TrimSpace(stdout))
}

//
// all of our test helpers
//

// setup function for all tests
func TestMain(m *testing.M) {
	os.Setenv("CLIFORCE_COLOR", "1")
	m.Run()
}

func captureMain(t *testing.T, args []string, stdin string) (exit int, stdout string) {
	exit = didntExit
	_, stdout = capture(t, args, stdin, func() bool {
		return main0(func(code int) { exit = code })
	})
	return
}

func capture[T any](t *testing.T, args []string, stdin string, fn func() T) (result T, stdout string) {
	// mock args
	os.Args = append([]string{"tennis"}, args...)
	// mock stdin/stdout
	oldStdin, oldStdout := os.Stdin, os.Stdout
	defer func() { os.Stdin, os.Stdout = oldStdin, oldStdout }()
	inRead, inWrite, _ := os.Pipe()
	outRead, outWrite, _ := os.Pipe()
	os.Stdin, os.Stdout = inRead, outWrite
	if len(stdin) == 0 {
		t.Setenv("FAKE_IS_TERMINAL", "1")
	} else {
		t.Setenv("FAKE_IS_TERMINAL", "")
	}
	inWrite.WriteString(stdin)

	// go
	inWrite.Close()
	result = fn()

	// collect stdout
	obuf := bytes.NewBuffer(nil)
	outWrite.Close()
	io.Copy(obuf, outRead)
	stdout = obuf.String()
	return
}
