package tennis

import (
	"bufio"
	"fmt"
	"io"
	"os"

	"github.com/charmbracelet/colorprofile"
	"github.com/charmbracelet/lipgloss/v2"
	"golang.org/x/term"
)

//
// TODO
// theme/color
// downsampling colors?
// row numbers
// main
// tests
//

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
	styles  *styles
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
	//
	// sanity checks
	//

	t.records = records
	if len(t.records) == 0 {
		return nil
	}
	t.headers = t.records[0]
	if len(t.headers) == 0 {
		return nil
	}

	nfields := len(t.records[0])
	for ii, record := range t.records {
		if len(record) != nfields {
			return fmt.Errorf("row %d has a different number of fields (can't be ragged)", ii+1)
		}
	}

	//
	// setup
	//

	if t.Color == ColorAuto {
		if colorprofile.Detect(os.Stderr, os.Environ()) >= colorprofile.ANSI {
			t.Color = ColorAlways
		} else {
			t.Color = ColorNever
		}
	}
	if t.TermWidth == 0 {
		termwidth, _, err := term.GetSize(int(os.Stdout.Fd()))
		if err != nil {
			t.TermWidth = DEFAULT_TERM_WIDTH
		} else {
			t.TermWidth = termwidth
		}
	}
	if t.Theme == ThemeAuto && t.Color != ColorNever {
		if lipgloss.HasDarkBackground(os.Stdin, os.Stderr) {
			t.Theme = ThemeDark
		} else {
			t.Theme = ThemeLight
		}
	}

	//
	// layout
	//

	t.widths = t.measure()
	t.layout = t.autolayout()
	t.styles = t.createStyles()

	//
	// render
	//

	t.render()
	return nil
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
