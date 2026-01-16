package main

import (
	"encoding/csv"
	"fmt"
	"os"
)

type Table struct {
	opts    *Options
	csv     *csv.Reader
	headers []string
	rows    [][]string
	widths  []int
	layout  []int
}

func Tennis(opts *Options) {
	table := &Table{opts: opts}

	// open file
	file, err := os.Open(opts.File)
	if err != nil {
		Fatal("error opening file", err)
	}
	defer file.Close()

	// read CSV
	table.csv = csv.NewReader(file)
	table.rows, err = table.csv.ReadAll()
	if err != nil {
		Fatal("error reading CSV", err)
	}

	// layout
	analyze(table)
	table.layout = AutoLayout(table.widths, TermWidth())

	// render
	Render(table)
}

//
// helpers
//

func analyze(table *Table) {
	if len(table.rows) == 0 {
		Fatal("file is empty", nil)
	}

	nfields := table.csv.FieldsPerRecord
	widths := make([]int, nfields)
	for ii, row := range table.rows {
		if len(row) != nfields {
			Fatal(fmt.Sprintf("row %d has a different number of fields (can't be jagged)", ii+1), nil)
		}
		for ii, data := range row {
			widths[ii] = max(widths[ii], len(data))
		}
	}
	table.widths = widths
	table.headers, table.rows = table.rows[0], table.rows[1:]
}
