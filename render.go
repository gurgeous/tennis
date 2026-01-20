package tennis

import (
	"strings"

	"github.com/charmbracelet/lipgloss/v2"
	"github.com/clipperhouse/displaywidth"
)

var (
	// box and friends
	BOX = [][]rune{
		[]rune("╭─┬─╮"), // 0
		[]rune("│ │ │"), // 1
		[]rune("├─┼─┤"), // 2
		[]rune("╰─┴─╯"), // 3
	}
	NW = BOX[0][0]
	N  = BOX[0][2]
	NE = BOX[0][4]
	W  = BOX[2][0]
	C  = BOX[2][2]
	E  = BOX[2][4]
	SW = BOX[3][0]
	S  = BOX[3][2]
	SE = BOX[3][4]

	// horizontal and vertical lines
	BAR  = BOX[0][1]
	PIPE = BOX[1][0]

	PLACEHOLDER = "—"
	ELLIPSIS    = "…"
)

func (t *Table) render() {
	t.renderSeparator(NW, N, NE)
	t.renderRow(0)
	t.renderSeparator(W, C, E)
	for ii := range t.records {
		if ii != 0 {
			t.renderRow(ii)
		}
	}
	t.renderSeparator(SW, S, SE)
	t.w.Flush()
}

func (t *Table) renderSeparator(l, m, r rune) {
	var buf strings.Builder
	for ii, width := range t.layout {
		if ii == 0 {
			buf.WriteRune(l)
		} else {
			buf.WriteRune(m)
		}
		for range width + 2 {
			buf.WriteRune(BAR)
		}
	}
	buf.WriteRune(r)
	str := buf.String()
	str = t.styles.chrome.Render(str)
	t.w.WriteString(str)
	t.w.WriteRune('\n')
}

func (t *Table) renderRow(row int) {
	pipe := string(PIPE)

	w := t.w
	w.WriteString(pipe)
	for ii, str := range t.records[row] {
		if len(str) == 0 {
			str = PLACEHOLDER
		}

		// layout
		str = fit(str, t.layout[ii])

		// style
		var style *lipgloss.Style
		// if header {
		// 	style = &Headers[ii%len(Headers)]
		if str == "-" {
			style = &t.styles.chrome
		} else {
			style = &t.styles.field
		}
		str = style.Render(str)

		// write
		w.WriteString(" ")
		w.WriteString(str)
		w.WriteString(" ")
		w.WriteString(pipe)
	}
	w.WriteRune('\n')
}

func fit(str string, width int) string {
	n := displaywidth.String(str)
	if n <= width {
		return str + strings.Repeat(" ", width-n)
	}
	return displaywidth.TruncateString(str, width, ELLIPSIS)
}
