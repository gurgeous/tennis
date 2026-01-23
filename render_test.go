package tennis

import (
	"bufio"
	"strings"
	"testing"

	"github.com/charmbracelet/colorprofile"
	"github.com/charmbracelet/lipgloss/v2"
	"github.com/stretchr/testify/assert"
)

const (
	ESC = "\x1b"       // escape
	R   = ESC + "[31m" // red
	G   = ESC + "[32m" // green
	Y   = ESC + "[33m" // yellow
	B   = ESC + "[34m" // blue
	M   = ESC + "[35m" // magenta
	X   = ESC + "[m"   // reset
)

func TestRenderSep(t *testing.T) {
	table := fakeTable()
	table.renderSep('L', 'M', 'R')
	assert.Equal(t, "L────M─────────M─────M────R", drain(table))
}

func TestRenderTitle(t *testing.T) {
	table := fakeTable()
	table.renderTitle()
	assert.Equal(t, "│"+Y+"foo"+X+"│", drain(table))
}

func TestRenderRow(t *testing.T) {
	table := fakeTable()
	table.renderRow(0)
	assert.Equal(t, "│"+B+"#"+X+"│"+M+"h"+X+"│"+B+"h2"+X+"│"+M+"h3"+X+"│", drain(table))
	table.renderRow(1)
	assert.Equal(t, "│"+R+"1"+X+"│"+G+"abcdefg"+X+"│"+G+"a"+X+"│"+G+"ab"+X+"│", drain(table))
}

func TestRenderCell(t *testing.T) {
	table := fakeTable()
	table.renderCell("h", 0, 1)
	assert.Equal(t, M+"h"+X+"│", drain(table))
}

func TestExactly(t *testing.T) {
	assert.Equal(t, "hello     ", exactly("hello", 10, left))
	assert.Equal(t, "  hi  ", exactly("hi", 6, center))
	assert.Equal(t, "exact", exactly("exact", 5, left))
	assert.Equal(t, "this is…", exactly("this is too long", 8, left))
	assert.Equal(t, "👋 hello 😊  ", exactly("👋 hello 😊", 13, left))
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
