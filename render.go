package tennis

import (
	"strconv"
	"strings"

	"github.com/charmbracelet/lipgloss/v2"
	"github.com/clipperhouse/displaywidth"
)

const (
	placeholder = "—"
	ellipsis    = "…"
)

var (
	// box and friends
	box = [][]rune{
		[]rune("╭─┬─╮"), // 0
		[]rune("│ │ │"), // 1
		[]rune("├─┼─┤"), // 2
		[]rune("╰─┴─╯"), // 3
	}
	nw = box[0][0]
	n  = box[0][2]
	ne = box[0][4]
	w  = box[2][0]
	c  = box[2][2]
	e  = box[2][4]
	sw = box[3][0]
	s  = box[3][2]
	se = box[3][4]

	// horizontal and vertical lines
	bar  = box[0][1]
	pipe = box[1][0]
)

func (t *Table) render() {
	t.pipe = t.styles.chrome.Render(string(pipe))

	t.renderSep(nw, n, ne)
	t.renderRow(0)
	t.renderSep(w, c, e)
	for ii := range t.records {
		if ii != 0 {
			t.renderRow(ii)
		}
	}
	t.renderSep(sw, s, se)
	_ = t.w.Flush()
}

func (t *Table) renderSep(l, m, r rune) {
	buf := &t.buf
	buf.Reset()
	for ii, width := range t.layout {
		if ii == 0 {
			buf.WriteRune(l)
		} else {
			buf.WriteRune(m)
		}
		for range width + 2 {
			buf.WriteRune(bar)
		}
	}
	buf.WriteRune(r)
	str := t.styles.chrome.Render(buf.String())
	t.writeLine(str)
}

func (t *Table) renderRow(row int) {
	col := 0
	buf := &t.buf
	buf.Reset()
	buf.WriteString(t.pipe)

	if t.RowNumbers {
		var data string
		if row == 0 {
			data = "#"
		} else {
			data = strconv.Itoa(row)
		}
		t.renderCell(data, row, col)
		col++
	}

	for _, data := range t.records[row] {
		t.renderCell(data, row, col)
		col++
	}
	t.writeLine(buf.String())
}

func (t *Table) renderCell(data string, row int, col int) {
	buf := &t.buf

	// is this cell empty?
	isPlaceholder := len(data) == 0
	if isPlaceholder {
		data = placeholder
	}

	// choose style
	var style *lipgloss.Style
	switch {
	case row == 0:
		style = &t.styles.headers[col%len(t.styles.headers)]
	case isPlaceholder:
		style = &t.styles.chrome
	case col == 0 && t.RowNumbers:
		style = &t.styles.chrome
	default:
		style = &t.styles.field
	}

	// render
	data = exactly(data, t.layout[col])
	data = style.Render(data)

	// append
	buf.WriteRune(' ')
	buf.WriteString(data)
	buf.WriteRune(' ')
	buf.WriteString(t.pipe)
}

func (t *Table) writeLine(str string) {
	// errors can be checked later on the writer
	_, _ = t.w.WriteString(str)
	_, _ = t.w.WriteRune('\n')
}

func exactly(str string, width int) string {
	n := displaywidth.String(str)
	if n <= width {
		return str + strings.Repeat(" ", width-n)
	}
	return displaywidth.TruncateString(str, width, ellipsis)
}
