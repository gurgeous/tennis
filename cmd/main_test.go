package main

import (
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

	_, stdout := captureMain(t, []string{"--color=never"}, strings.TrimSpace(input))
	assert.Equal(t, strings.TrimSpace(exp), strings.TrimSpace(stdout))
}
