package main

import (
	"fmt"
	"strings"

	"github.com/charmbracelet/lipgloss"
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

	ELLIPSIS = "…"
)

func Render(state *State) {
	renderSep(state.layout, NW, N, NE)
	renderRow(state.rows[0], state.layout, true)
	renderSep(state.layout, W, C, E)
	for ii, row := range state.rows {
		if ii == 0 {
			continue
		}
		renderRow(row, state.layout, false)
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
	fmt.Println(Field.Render(buf.String()))
}

func renderRow(record []string, layout []int, header bool) {
	pipe := Chrome.Render(string(PIPE))

	var buf strings.Builder
	buf.WriteString(pipe)
	for ii, data := range record {
		var style *lipgloss.Style
		if header {
			style = &Headers[ii%len(Headers)]
		} else {
			style = &Field
		}
		data = fit(data, layout[ii])
		data = style.Render(data)

		buf.WriteString(" ")
		buf.WriteString(data)
		buf.WriteString(" ")
		buf.WriteString(pipe)
	}
	fmt.Println(buf.String())
}

func fit(str string, width int) string {
	if width == 0 {
		return ""
	}
	if len(str) <= width {
		return str + strings.Repeat(" ", width-len(str))
	}
	return str[:width-1] + ELLIPSIS
}
