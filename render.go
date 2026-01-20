package tennis

import (
	"strings"

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
	for ii := range t.records[1:] {
		t.renderRow(ii)
	}
	t.renderSeparator(SW, S, SE)
	t.w.Flush()
}

func (t *Table) renderSeparator(l, m, r rune) {
	w := t.w
	for ii, width := range t.layout {
		if ii == 0 {
			w.WriteRune(l)
		} else {
			w.WriteRune(m)
		}
		for range width + 2 {
			w.WriteRune(BAR)
		}
	}
	w.WriteRune(r)
	w.WriteRune('\n')
}

func (t *Table) renderRow(row int) {
	PIPE_STYLED := string(PIPE)

	w := t.w
	w.WriteString(PIPE_STYLED)
	for ii, data := range t.records[row] {
		if len(data) == 0 {
			data = PLACEHOLDER
		}

		// render w/ style
		// var style *lipgloss.Style
		// if header {
		// 	style = &Headers[ii%len(Headers)]
		// } else if data == "-" {
		// 	style = &Chrome
		// } else {
		// 	style = &Field
		// }
		// data = style.Render(data)

		data = fit(data, t.layout[ii])

		w.WriteString(" ")
		w.WriteString(data)
		w.WriteString(" ")
		w.WriteString(PIPE_STYLED)
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
