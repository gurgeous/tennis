package main

import (
	"fmt"
	"strings"

	"github.com/charmbracelet/lipgloss"
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

	ELLIPSIS = "…"
)

func Render(table *Table) {
	renderSep(table.layout, NW, N, NE)
	renderRow(table.headers, table.layout, true)
	renderSep(table.layout, W, C, E)
	for _, row := range table.rows {
		renderRow(row, table.layout, false)
	}
	renderSep(table.layout, SW, S, SE)
}

func renderSep(layout []int, l, m, r rune) {
	var buf strings.Builder
	for ii, width := range layout {
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
	fmt.Println(Chrome.Render(buf.String()))
}

func renderRow(record []string, layout []int, header bool) {
	PIPE_STYLED := Chrome.Render(string(PIPE))

	var buf strings.Builder

	buf.WriteString(PIPE_STYLED)
	for ii, data := range record {
		data = fit(data, layout[ii])

		// render w/ style
		var style *lipgloss.Style
		if header {
			style = &Headers[ii%len(Headers)]
		} else {
			style = &Field
		}

		buf.WriteString(" ")
		buf.WriteString(style.Render(data))
		buf.WriteString(" ")
		buf.WriteString(PIPE_STYLED)
	}

	fmt.Println(buf.String())
}

func fit(str string, width int) string {
	if len(str) <= width {
		return str + strings.Repeat(" ", width-len(str))
	}
	return str[:width-1] + ELLIPSIS
}
