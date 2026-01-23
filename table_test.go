package tennis

import (
	"bufio"
	"strings"
	"testing"

	"github.com/charmbracelet/colorprofile"
	"github.com/charmbracelet/lipgloss/v2"
	"github.com/stretchr/testify/assert"
)

func TestTable(t *testing.T) {
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

	output := &strings.Builder{}
	table := &Table{Output: output}
	table.Write(strings.NewReader(strings.TrimSpace(input)))
	assert.Equal(t, strings.TrimSpace(exp), strings.TrimSpace(output.String()))
}

//
// helpers
//

func fakeTable() *Table {
	return &Table{
		Color:      ColorAlways,
		Theme:      ThemeDark,
		TermWidth:  100,
		RowNumbers: true,
		Title:      "foo",
		ctx: context{
			w:       bufio.NewWriter(&strings.Builder{}),
			headers: []string{"#", "h", "h2", "h3"},
			records: [][]string{
				{"h", "h2", "h3"},
				{"abcdefg", "a", "ab"},
				{"a", "abc", "z"},
			},
			layout:  []int{2, 7, 3, 2},
			profile: colorprofile.TrueColor,
			styles: &styles{
				chrome: lipgloss.NewStyle().Foreground(lipgloss.Color("1")), // red
				field:  lipgloss.NewStyle().Foreground(lipgloss.Color("2")), // green
				title:  lipgloss.NewStyle().Foreground(lipgloss.Color("3")), // yellow
				headers: []lipgloss.Style{
					lipgloss.NewStyle().Foreground(lipgloss.Color("4")), // blue
					lipgloss.NewStyle().Foreground(lipgloss.Color("5")), // magenta
				},
			},
			pipe: "│",
		},
	}
}

func drain(t *Table) string {
	buf := &t.ctx.buf
	defer buf.Reset()
	return strings.ReplaceAll(buf.String(), " ", "")
}
