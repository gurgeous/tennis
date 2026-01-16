package main

// TODO
//
// - styles
// - cli flags (zebra, color=always or whatever)
// - grapheme/truncation (and benchmarks)
// - feature: row numbers
// - feature: placeholders
//

import (
	"encoding/csv"
	"fmt"
	"os"
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

	// layout
	state.dataWidth = measureData(state)
	state.layout = AutoLayout(state.dataWidth, TermWidth())

	// render
	Render(state)
}

//
// helpers
//

func measureData(state *State) []int {
	nfields := state.csv.FieldsPerRecord
	dataWidth := make([]int, nfields)
	for ii, row := range state.rows {
		if len(row) != nfields {
			Fatal(fmt.Sprintf("row %d has a different number of fields (can't be jagged)", ii+1), nil)
		}
		for ii, data := range row {
			dataWidth[ii] = max(dataWidth[ii], len(data))
		}
	}
	return dataWidth
}
