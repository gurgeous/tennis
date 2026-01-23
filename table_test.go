package tennis

import (
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestTable(t *testing.T) {
	const input = "a,b\nc,d"

	exp := "" +
		"CH╭────┬────╮RE\n" +
		"CH│RE H1a RE CH│RE H2b RE CH│RE\n" +
		"CH├────┼────┤RE\n" +
		"CH│RE FIc RE CH│RE FId RE CH│RE\n" +
		"CH╰────┴────╯RE\n"
	exp = strings.ReplaceAll(exp, "CH", "\x1b[38;2;107;114;128m")   // chrome
	exp = strings.ReplaceAll(exp, "RE", "\x1b[m")                   // reset
	exp = strings.ReplaceAll(exp, "H1", "\x1b[1;38;2;255;97;136m")  // first header
	exp = strings.ReplaceAll(exp, "H2", "\x1b[1;38;2;252;152;103m") // second header
	exp = strings.ReplaceAll(exp, "FI", "\x1b[38;2;229;231;235m")   // field

	output := &strings.Builder{}
	table := &Table{
		Color:  ColorAlways,
		Theme:  ThemeDark,
		Output: output,
	}
	table.Write(strings.NewReader(input))
	assert.Equal(t, exp, output.String())
}
