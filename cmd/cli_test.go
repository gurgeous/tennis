package main

import (
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
)

//
// simple end-to-end test
//

func TestMain(t *testing.T) {
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

	_, stdout, _ := withContext(t, []string{}, strings.TrimSpace(input), main0)
	assert.Equal(t, strings.TrimSpace(exp), strings.TrimSpace(stdout))
}
