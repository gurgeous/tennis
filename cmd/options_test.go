package main

import (
	"bytes"
	"io"
	"os"
	"testing"

	"github.com/stretchr/testify/assert"
)

const didntExit = -999

func TestOptions(t *testing.T) {
	options, exit, _ := captureOptions(t, []string{"-n", "--color=never", "--theme=light"}, "something")
	assert.Equal(t, didntExit, exit)
	assert.NotNil(t, options.Input)
	assert.True(t, options.RowNumbers)
	assert.Equal(t, options.Color, "never")
	assert.Equal(t, options.Theme, "light")
}

func TestOptionsEmpty(t *testing.T) {
	_, exit, stdout := captureOptions(t, []string{}, "")
	assert.Equal(t, 0, exit)
	assert.Contains(t, stdout, "try 'tennis --help'")
}

func TestOptionsBogus(t *testing.T) {
	_, exit, stdout := captureOptions(t, []string{"--bogus"}, "")
	assert.Equal(t, 80, exit)
	assert.Contains(t, stdout, "unknown flag --bogus")
}

//
// test helpers
//

func captureMain(t *testing.T, args []string, stdin string) (exit int, stdout string) {
	exit = didntExit
	_, stdout = capture(t, args, stdin, func() bool {
		return main0(func(code int) { exit = code })
	})
	return
}

func captureOptions(t *testing.T, args []string, stdin string) (opts *Options, exit int, stdout string) {
	exit = didntExit
	opts, stdout = capture(t, args, stdin, func() *Options {
		return options(func(code int) { exit = code })
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
