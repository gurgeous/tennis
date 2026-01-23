package tennis

import (
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestTableColor(t *testing.T) {
	const input = "a,b\nc,d"
	exp := "" +
		"CH╭────┬────╮RE\n" +
		"CH│RE H1a RE CH│RE H2b RE CH│RE\n" +
		"CH├────┼────┤RE\n" +
		"CH│RE FIc RE CH│RE FId RE CH│RE\n" +
		"CH╰────┴────╯RE\n"
	exp = strings.ReplaceAll(exp, "CH", "\x1b[38;2;107;114;128m")   // chrome
	exp = strings.ReplaceAll(exp, "H1", "\x1b[1;38;2;255;97;136m")  // first header
	exp = strings.ReplaceAll(exp, "H2", "\x1b[1;38;2;252;152;103m") // second header
	exp = strings.ReplaceAll(exp, "FI", "\x1b[38;2;229;231;235m")   // field
	exp = strings.ReplaceAll(exp, "RE", "\x1b[m")                   // reset

	output := &strings.Builder{}
	table := &Table{Color: ColorAlways, Theme: ThemeDark, Output: output}
	table.Write(strings.NewReader(input))
	assert.Equal(t, exp, output.String())
}

func TestTableAscii(t *testing.T) {
	const input = "a,b\nc,d"
	const exp = `
╭────┬────╮
│ a  │ b  │
├────┼────┤
│ c  │ d  │
╰────┴────╯
`
	output := &strings.Builder{}
	table := &Table{Color: ColorNever, Output: output}
	table.Write(strings.NewReader(input))
	AssertEqualTrim(t, exp, output.String())
}

func TestTableRagged(t *testing.T) {
	input := [][]string{
		{"a", "b"},
		{"c"},
		{"d", "e", "f"},
	}
	const exp = `
╭────┬────╮
│ a  │ b  │
├────┼────┤
│ c  │ —  │
│ d  │ e  │
╰────┴────╯
`
	output := &strings.Builder{}
	table := &Table{Color: ColorNever, Output: output}
	table.WriteRecords(input)
	AssertEqualTrim(t, exp, output.String())
}

func TestTableDebug(t *testing.T) {
	const input = "a,b\nc,d"
	t.Setenv("TENNIS_DEBUG", "1")
	table := &Table{Output: &strings.Builder{}}
	table.Write(strings.NewReader(input))
}
