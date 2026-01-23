package main

import (
	"bytes"
	"fmt"
	"io"
	"os"
	"testing"

	"github.com/gurgeous/tennis"
	"github.com/stretchr/testify/assert"
)

func TestOptionsEmpty(t *testing.T) {
	_, stdout, exitCode := withContext(t, []string{}, "", options)
	assert.Equal(t, 0, exitCode)
	assert.Contains(t, stdout, "try 'tennis --help'")
}

func TestOptionsBogus(t *testing.T) {
	_, stdout, exitCode := withContext(t, []string{"--bogus"}, "", options)
	assert.Equal(t, 80, exitCode)
	assert.Contains(t, stdout, "unknown flag --bogus")
}

func TestOptions(t *testing.T) {
	o, stdout, exitCode := withContext(t, []string{"-n", "--color=never", "--theme=light"}, "foo", options)

	fmt.Println(stdout)
	assert.Equal(t, -1, exitCode)
	assert.True(t, o.Table.RowNumbers)
	assert.Equal(t, o.Table.Color, tennis.ColorNever)
	assert.Equal(t, o.Table.Theme, tennis.ThemeLight)
}

//
// helpers
//

func withContext[R any](t *testing.T, args []string, stdin string, fn func(ctx *MainContext) R) (result R, stdout string, exitCode int) {
	// pipes
	inRead, inWrite, _ := os.Pipe()
	outRead, outWrite, _ := os.Pipe()
	if len(stdin) == 0 {
		t.Setenv("TTY_FORCE", "1")
	} else {
		t.Setenv("TTY_FORCE", "")
	}
	inWrite.WriteString(stdin)
	inWrite.Close()

	// run
	exitCode = -1
	ctx := &MainContext{Args: args, Input: inRead, Output: outWrite, Exit: func(n int) { exitCode = n }}
	result = fn(ctx)
	outWrite.Close()

	// collect stdout
	buf := bytes.NewBuffer(nil)
	io.Copy(buf, outRead)
	stdout = buf.String()

	return
}
