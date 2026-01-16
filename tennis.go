package main

import (
	"encoding/csv"
	"fmt"
	"os"
	"strings"

	"github.com/rivo/uniseg"
)

type State struct {
	csv       *csv.Reader
	rows      [][]string
	dataWidth []int
	layout    []int
}

func Tennis(args *Options) {
	file, err := os.Open(args.File)
	if err != nil {
		Fatal("error opening file", err)
	}
	defer file.Close()

	state := &State{}

	// read CSV
	state.csv = csv.NewReader(file)
	state.rows, err = state.csv.ReadAll()
	if err != nil {
		Fatal("error reading CSV", err)
	}
	if len(state.rows) == 0 {
		Fatal("file is empty", nil)
	}

	// measure raw data width
	state.dataWidth = measureData(state)
	fmt.Printf("data   %v\n", state.dataWidth)

	// now layout data into termwidth
	state.layout = AutoLayout(state.dataWidth, TermWidth())
	fmt.Printf("layout %v\n", state.layout)

	// and render
	render(state)
	// for _, row := range state.rows {
	// 	for i, data := range row {
	// 		// Pad or truncate data to fit layout width
	// 		width := state.layout[i]
	// 		// displayLen := uniseg.GraphemeClusterCount(data)
	// 		if len(data) > width {
	// 			fmt.Printf("%s…", data[:width-1])
	// 		} else {
	// 			fmt.Printf("%-*s", width, data)
	// 		}
	// 		if i < len(row)-1 {
	// 			fmt.Print(" ")
	// 		}
	// 	}
	// 	fmt.Println()
	// }
}

func measureData(state *State) []int {
	nfields := state.csv.FieldsPerRecord
	dataWidth := make([]int, nfields)
	for ii, row := range state.rows {
		if len(row) != nfields {
			Fatal(fmt.Sprintf("row %d has a different number of fields (can't be jagged)", ii+1), nil)
		}
		for ii, data := range row {
			// w := len(data)
			dataWidth[ii] = max(dataWidth[ii], uniseg.GraphemeClusterCount(data))
		}
	}
	return dataWidth
}

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
)

func renderSeparator(layout []int, l, m, r rune) string {
	var buf []rune
	for ii, width := range layout {
		if ii == 0 {
			buf = append(buf, l)
		} else {
			buf = append(buf, m)
		}
		for range width + 2 {
			buf = append(buf, BAR)
		}
	}
	buf = append(buf, r)
	return string(buf)
}

// REMIND: truncate/pad/color/graphemes

func renderRow(record []string, layout []int) {
	var line strings.Builder
	line.WriteRune(PIPE)
	for _, field := range record {
		line.WriteString(" ")
		line.WriteString(field)
		line.WriteString(" ")
		line.WriteRune(PIPE)
	}
	line.WriteString("\n")
	fmt.Println(line.String())
}

func render(state *State) {
	// fmt.Println("a")
	fmt.Println(renderSeparator(state.layout, NW, N, NE))
	renderRow(state.rows[0], state.layout)
	fmt.Println(renderSeparator(state.layout, W, C, E))
	for _, row := range state.rows {
		renderRow(row, state.layout)
	}
	fmt.Println(renderSeparator(state.layout, SW, S, SE))
}
