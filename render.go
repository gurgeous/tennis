package tennis

import (
	"strconv"
	"strings"

	"github.com/charmbracelet/x/ansi"
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
	t.ctx.pipe = t.ctx.styles.render(t.ctx.styles.chrome, string(pipe))

	if len(t.Title) > 0 {
		t.renderSep(nw, bar, ne)
		t.renderTitle()
		t.renderSep(w, n, e)
	} else {
		t.renderSep(nw, n, ne)
	}
	t.renderRow(0)
	t.renderSep(w, c, e)
	for ii := range t.ctx.records {
		if ii != 0 {
			t.renderRow(ii)
		}
	}
	t.renderSep(sw, s, se)
	t.ctx.w.Flush() //nolint:gosec
}

func (t *Table) renderSep(l, m, r rune) {
	buf := &t.ctx.buf
	buf.Reset()
	for ii, width := range t.ctx.layout {
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
	t.writeLine(t.ctx.styles.render(t.ctx.styles.chrome, buf.String()))
}

func (t *Table) renderTitle() {
	const edges = 4 // |•xxxxxx•|
	str := exactly(t.Title, tableWidth(t.ctx.layout)-edges, center)

	buf := &t.ctx.buf
	buf.Reset()
	buf.WriteString(t.ctx.pipe)
	buf.WriteRune(' ')
	t.ctx.styles.append(buf, t.ctx.styles.title, str)
	buf.WriteRune(' ')
	buf.WriteString(t.ctx.pipe)
	t.writeLine(buf.String())
}

func (t *Table) renderRow(row int) {
	col := 0
	buf := &t.ctx.buf
	buf.Reset()
	buf.WriteString(t.ctx.pipe)

	if t.RowNumbers {
		var str string
		if row == 0 {
			str = "#"
		} else {
			str = strconv.Itoa(row)
		}
		t.renderCell(str, row, col)
		col++
	}

	for _, str := range t.ctx.records[row] {
		t.renderCell(str, row, col)
		col++
	}
	t.writeLine(buf.String())
}

func (t *Table) renderCell(str string, row int, col int) {
	buf := &t.ctx.buf

	// is this cell empty? put in a placeolder
	isPlaceholder := len(str) == 0
	if isPlaceholder {
		const placeholder = "—"
		str = placeholder
	}
	str = exactly(str, t.ctx.layout[col], left)

	// choose style for this cell
	var style string
	switch {
	case row == 0:
		style = t.ctx.styles.headers[col%len(t.ctx.styles.headers)]
	case isPlaceholder:
		style = t.ctx.styles.chrome
	case col == 0 && t.RowNumbers:
		style = t.ctx.styles.chrome
	default:
		style = t.ctx.styles.field
	}

	// append
	buf.WriteRune(' ')
	t.ctx.styles.append(buf, style, str)
	buf.WriteRune(' ')
	buf.WriteString(t.ctx.pipe)
}

// errors can be checked later on the writer
//
//nolint:errcheck,gosec
func (t *Table) writeLine(str string) {
	t.ctx.w.WriteString(str)
	t.ctx.w.WriteRune('\n')
}

//
// exactly
//

type align int

const (
	left align = iota
	center
)

func exactly(str string, length int, align align) string {
	xtra := length - ansi.StringWidth(str)

	if xtra > 0 {
		switch align {
		case left:
			str += strings.Repeat(" ", xtra)
		case center:
			half := xtra / 2
			str = strings.Repeat(" ", half) + str + strings.Repeat(" ", xtra-half)
		}
	} else if xtra < 0 {
		const ellipsis = "…"
		str = ansi.Truncate(str, length, ellipsis)
	}
	return str
}
