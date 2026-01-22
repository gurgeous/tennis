package main

import (
	"bytes"
	"io"
	"os"
	"testing"
)

//
// helpers that are used for testing
//

// setup function for all tests
func TestMain(m *testing.M) {
	panic("no")
	os.Setenv("CLICOLOR_FORCE", "1")
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
