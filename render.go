package main

import (
	"fmt"
	"strings"
)

var (
	BOX = [][]rune{
		[]rune("╭─┬─╮"), // 0
		[]rune("│ │ │"), // 1
		[]rune("├─┼─┤"), // 2
		[]rune("╰─┴─╯"), // 3
	}

	// take these from BOX
	NW = rune(BOX[0][0])
	N  = rune(BOX[0][2])
	NE = rune(BOX[0][4])
	W  = rune(BOX[2][0])
	C  = rune(BOX[2][2])
	E  = rune(BOX[2][4])
	SW = rune(BOX[3][0])
	S  = rune(BOX[3][2])
	SE = rune(BOX[3][4])

	// horizontal and vertical lines
	BAR  = rune(BOX[0][1])
	PIPE = rune(BOX[1][0])

	ELLIPSIS = '…'
)

func Render(state *State) {
	renderSep(state.layout, NW, N, NE)
	renderRow(state.rows[0], state.layout)
	renderSep(state.layout, W, C, E)
	for _, row := range state.rows {
		renderRow(row, state.layout)
	}
	renderSep(state.layout, SW, S, SE)
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
	fmt.Println(buf.String())
}

func renderRow(record []string, layout []int) {
	var buf strings.Builder
	buf.WriteRune(PIPE)
	for ii, data := range record {
		buf.WriteString(" ")
		cell(&buf, data, layout[ii])
		buf.WriteString(" ")
		buf.WriteRune(PIPE)
	}
	fmt.Println(buf.String())
}

func cell(buf *strings.Builder, str string, width int) {
	if width == 0 {
		return
	}
	if len(str) <= width {
		buf.WriteString(str)
		buf.WriteString(strings.Repeat(" ", width-len(str)))
	} else {
		buf.WriteString(str[:width-1])
		buf.WriteRune(ELLIPSIS)
	}
}
