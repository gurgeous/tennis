package main

import (
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

func captureOptions(t *testing.T, args []string, stdin string) (opts *Options, exit int, stdout string) {
	exit = didntExit
	opts, stdout = capture(t, args, stdin, func() *Options {
		return options(func(code int) { exit = code })
	})
	return
}
