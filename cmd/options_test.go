package main

import (
	"bytes"
	"io"
	"os"
	"testing"

	"github.com/stretchr/testify/assert"
)

func testOptions(t *testing.T, args []string, stdin string) (exitCode int, stdout string) {
	// mock args
	os.Args = append([]string{"tennis"}, args...)
	// mock stdin
	// mock stdin/stdout
	oldStdin, oldStdout := os.Stdin, os.Stdout
	defer func() { os.Stdin, os.Stdout = oldStdin, oldStdout }()
	inRead, inWrite, _ := os.Pipe()
	outRead, outWrite, _ := os.Pipe()
	os.Stdin, os.Stdout = inRead, outWrite
	if len(stdin) == 0 {
		t.Setenv("FAKE_IS_TERMINAL", "1")
	}
	inWrite.WriteString(stdin)
	// mock exit
	exitCode = -1
	exitFn := func(code int) { exitCode = code }

	// go
	options(exitFn)

	// collect stdout
	obuf := bytes.NewBuffer(nil)
	outWrite.Close()
	io.Copy(obuf, outRead)
	stdout = obuf.String()

	return
}

func TestOptions(t *testing.T) {
	exitCode, stdout := testOptions(t, []string{}, "")
	assert.Equal(t, 0, exitCode)
	assert.Contains(t, stdout, "try 'tennis --help'")
}
