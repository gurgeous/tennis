package tennis

import (
	"bufio"
	"encoding/csv"
	"os"
)

//
// table config & state
//

type Table struct {
	Color      Color
	Theme      Theme
	RowNumbers bool
	rows       [][]string // csv data
	layout     []int      // calculated column widths
	w          *bufio.Writer
}

type Theme int

const (
	ThemeAuto Theme = iota
	ThemeDark
	ThemeLight
)

type Color int

const (
	ColorAuto Color = iota
	ColorAlways
	ColorNever
)

//
// main entry points
//

// open csv
// file, err := os.Open(options.File)
// if err != nil {
// 	tennis.Fatal("error opening file", err)
// }
// defer file.Close()
// csv := csv.NewReader(file)

// // setup table
// table := tennis.NewTable(csv)
// fmt.Printf("%#v\n", table)
// if err := table.Print(); err != nil {
// 	tennis.Fatal("table.Print failed", err)
// }
// fmt.Printf("%#v\n", "gub")

func (t *Table) PrintFilename(name string) error {
	file, err := os.Open(name)
	if err != nil {
		return err
	}
	defer file.Close()
	return t.PrintFile(file)
}

func (t *Table) PrintFile(file *os.File) error {
	return t.PrintCsv(csv.NewReader(file))
}

func (t *Table) PrintCsv(r *csv.Reader) error {
	// read all rows
	rows, err := r.ReadAll()
	if err != nil {
		return err
	}

	// go!
}

func (t *Table) PrintTable(rows [][]string) {
}

// func Tennis(opts *Options) {

// 	// layout
// 	analyze(table)
// 	table.layout = AutoLayout(table.widths, TermWidth())

// 	// render
// 	Render(table)
// }

// //
// // helpers
// //

// func analyze(table *Table) {
// 	if len(table.rows) == 0 {
// 		Fatal("file is empty", nil)
// 	}

// 	nfields := table.csv.FieldsPerRecord
// 	widths := make([]int, nfields)
// 	for ii, row := range table.rows {
// 		if len(row) != nfields {
// 			Fatal(fmt.Sprintf("row %d has a different number of fields (can't be jagged)", ii+1), nil)
// 		}
// 		for ii, data := range row {
// 			widths[ii] = max(widths[ii], len(data))
// 		}
// 	}
// 	table.widths = widths
// 	table.headers, table.rows = table.rows[0], table.rows[1:]
// }
