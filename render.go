package tennis

import (
	"fmt"
	"strconv"
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

func (t *Table) render() error {
	t.pipe = t.styles.chrome.Render(string(PIPE))

	if err := t.renderSep(NW, N, NE); err != nil {
		return err
	}
	if err := t.renderRow(0); err != nil {
		return err
	}
	if err := t.renderSep(W, C, E); err != nil {
		return err
	}
	for ii := range t.records {
		if ii != 0 {
			if err := t.renderRow(ii); err != nil {
				return err
			}
		}
	}
	if err := t.renderSep(SW, S, SE); err != nil {
		return err
	}
	if err := t.w.Flush(); err != nil {
		return fmt.Errorf("error on tennis.render: %w", err)
	}
	return nil
}

func (t *Table) renderSep(l, m, r rune) error {
	buf := &t.buf
	buf.Reset()
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
	str := t.styles.chrome.Render(buf.String())
	return t.writeLine(str)
}

func (t *Table) renderRow(row int) error {
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
	return t.writeLine(buf.String())
}

func (t *Table) renderCell(data string, row int, col int) {
	buf := &t.buf

	placeholder := len(data) == 0
	if placeholder {
		data = PLACEHOLDER
	}

	// layout
	data = exactly(data, t.layout[col])

	// style
	var style *lipgloss.Style
	switch {
	case row == 0:
		style = &t.styles.headers[col%len(t.styles.headers)]
	case placeholder:
		style = &t.styles.chrome
	case col == 0 && t.RowNumbers:
		style = &t.styles.chrome
	default:
		style = &t.styles.field
	}
	data = style.Render(data)

	// append
	buf.WriteRune(' ')
	buf.WriteString(data)
	buf.WriteRune(' ')
	buf.WriteString(t.pipe)
}

func (t *Table) writeLine(str string) error {
	if _, err := t.w.WriteString(str); err != nil {
		return fmt.Errorf("tennis.writeLine: %w", err)
	}
	if _, err := t.w.WriteRune('\n'); err != nil {
		return fmt.Errorf("tennis.writeLine: %w", err)
	}
	return nil
}

func exactly(str string, width int) string {
	n := displaywidth.String(str)
	if n <= width {
		return str + strings.Repeat(" ", width-n)
	}
	return displaywidth.TruncateString(str, width, ELLIPSIS)
}
