package tennis

//
// TODO
// theme/color
// row numbers
// main
// tests

import (
	"bufio"
	"fmt"
	"io"
	"os"

	"golang.org/x/term"
)

//
// types
//

type Table struct {
	Color      Color
	TermWidth  int
	Theme      Theme
	RowNumbers bool
	// state
	w       *bufio.Writer
	headers []string
	records [][]string
	widths  []int
	layout  []int
}

type Color int

const (
	ColorAuto Color = iota
	ColorAlways
	ColorNever
)

type Theme int

const (
	ThemeAuto Theme = iota
	ThemeDark
	ThemeLight
)

const (
	DEFAULT_TERM_WIDTH = 80
	MIN_FIELD_WIDTH    = 2
)

//
// public
//

func NewTable(w io.Writer) *Table {
	return &Table{
		w: bufio.NewWriter(w),
	}
}

func (t *Table) WriteAll(records [][]string) error {
	t.records = records
	if len(t.records) == 0 {
		return nil
	}
	t.headers = t.records[0]
	if len(t.headers) == 0 {
		return nil
	}

	// sanity check - we don't allow ragged
	nfields := len(t.records[0])
	for ii, record := range t.records {
		if len(record) != nfields {
			return fmt.Errorf("row %d has a different number of fields (can't be ragged)", ii+1)
		}
	}

	// setup
	if t.TermWidth == 0 {
		t.TermWidth = getTermWidth()
	}
	if t.Color == ColorAuto {
		t.Color = getColor()
	}
	if t.Theme == ThemeAuto {
		t.Theme = getTheme()
	}

	// layout
	t.widths = t.measure()
	t.layout = t.autolayout()

	// render
	t.render()
	return nil
}

//
// getters that have to do some work
//

func getColor() Color {
	return ColorAlways
}

func getTheme() Theme {
	return ThemeDark
}

func getTermWidth() int {
	termwidth, _, err := term.GetSize(int(os.Stdout.Fd()))
	if err != nil {
		termwidth = DEFAULT_TERM_WIDTH
	}
	return termwidth
}

// Measure the size of each column. Fails if the records are ragged
func (t *Table) measure() []int {
	nfields := len(t.headers)
	widths := make([]int, nfields)
	for ii := range nfields {
		widths[ii] = MIN_FIELD_WIDTH
	}
	for _, record := range t.records {
		for ii, data := range record {
			widths[ii] = max(widths[ii], len(data))
		}
	}
	return widths
}
