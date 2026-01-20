package tennis

import (
	"fmt"
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
	if err := t.writeSeparator(NW, N, NE); err != nil {
		return err
	}
	if err := t.writeRow(0); err != nil {
		return err
	}
	if err := t.writeSeparator(W, C, E); err != nil {
		return err
	}
	for ii := range t.records {
		if ii != 0 {
			if err := t.writeRow(ii); err != nil {
				return err
			}
		}
	}
	if err := t.writeSeparator(SW, S, SE); err != nil {
		return err
	}
	if err := t.w.Flush(); err != nil {
		return fmt.Errorf("error on tennis.render: %w", err)
	}
	return nil
}

func (t *Table) writeSeparator(l, m, r rune) error {
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
	str := t.styles.chrome.Render(buf.String())
	return t.writeLine(str)
}

func (t *Table) writeRow(row int) error {
	var buf strings.Builder
	pipe := t.styles.chrome.Render(string(PIPE))

	buf.WriteString(pipe)
	for ii, data := range t.records[row] {
		// pre-process data
		placeholder := len(data) == 0
		if placeholder {
			data = PLACEHOLDER
		}

		// layout
		data = fit(data, t.layout[ii])

		// style
		var style *lipgloss.Style
		switch {
		case row == 0:
			style = &t.styles.headers[ii%len(t.styles.headers)]
		case placeholder:
			style = &t.styles.chrome
		default:
			style = &t.styles.field
		}
		data = style.Render(data)

		// write
		buf.WriteRune(' ')
		buf.WriteString(data)
		buf.WriteRune(' ')
		buf.WriteString(pipe)
	}
	return t.writeLine(buf.String())
}

func (t *Table) writeLine(str string) error {
	if _, err := t.w.WriteString(str); err != nil {
		return fmt.Errorf("error on tennis.writeLine: %w", err)
	}
	if _, err := t.w.WriteRune('\n'); err != nil {
		return fmt.Errorf("error on tennis.writeLine: %w", err)
	}
	return nil
}

func fit(str string, width int) string {
	n := displaywidth.String(str)
	if n <= width {
		return str + strings.Repeat(" ", width-n)
	}
	return displaywidth.TruncateString(str, width, ELLIPSIS)
}
