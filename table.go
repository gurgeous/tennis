package tennis

import (
	"bufio"
	"io"
	"os"
	"strconv"
	"strings"

	"github.com/charmbracelet/colorprofile"
	"github.com/charmbracelet/lipgloss/v2"
	"golang.org/x/term"
)

//
// TODO
// downsampling colors?
// row numbers
// main
// tests
//

//
// types
//

type Table struct {
	ColorChoice ColorChoice
	TermWidth   int
	ThemeChoice ThemeChoice
	RowNumbers  bool
	// internal
	w       *bufio.Writer
	headers []string
	records [][]string
	widths  []int
	layout  []int
	styles  *styles
	buf     strings.Builder
	pipe    string
}

type ColorChoice int

const (
	ColorChoiceAuto ColorChoice = iota
	ColorChoiceAlways
	ColorChoiceNever
)

type ThemeChoice int

const (
	ThemeChoiceAuto ThemeChoice = iota
	ThemeChoiceDark
	ThemeChoiceLight
)

const (
	defaultTermWidth = 80
	minFieldWidth    = 2
)

//
// public
//

func NewTable(w io.Writer) *Table {
	return &Table{w: bufio.NewWriter(w)}
}

func (t *Table) WriteAll(records [][]string) error {
	// edge cases
	t.records = records
	if len(t.records) == 0 {
		return nil
	}
	t.headers = records[0]
	if len(t.headers) == 0 {
		return nil
	}

	//
	// setup
	//

	if t.ColorChoice == ColorChoiceAuto {
		profile := colorprofile.Detect(t.w, os.Environ())
		if profile >= colorprofile.ANSI {
			t.ColorChoice = ColorChoiceAlways
		} else {
			t.ColorChoice = ColorChoiceNever
		}
	}
	if t.TermWidth == 0 {
		termwidth, _, err := term.GetSize(int(os.Stdout.Fd()))
		if err != nil {
			t.TermWidth = defaultTermWidth
		} else {
			t.TermWidth = termwidth
		}
	}
	if t.ThemeChoice == ThemeChoiceAuto && t.ColorChoice != ColorChoiceNever {
		if lipgloss.HasDarkBackground(os.Stdin, os.Stderr) {
			t.ThemeChoice = ThemeChoiceDark
		} else {
			t.ThemeChoice = ThemeChoiceLight
		}
	}

	// setup buffered write with downsampling

	//
	// layout
	//

	t.widths = t.measure()
	t.layout = t.autolayout()
	t.styles = t.createStyles()

	//
	// render
	//

	if err := t.render(); err != nil {
		return err
	}

	return nil
}

//
// helpers
//

// Measure the size of each column. Fails if the records are ragged
func (t *Table) measure() []int {
	widths := make([]int, len(t.headers))
	for ii := range widths {
		widths[ii] = minFieldWidth
	}
	for _, record := range t.records {
		for ii, data := range record {
			data = strings.TrimSpace(data)
			record[ii] = data
			widths[ii] = max(widths[ii], len(data))
		}
	}
	if t.RowNumbers {
		n := len(t.records) - 1
		ndigits := len(strconv.Itoa(n))
		unshift(&widths, max(ndigits, minFieldWidth))
	}
	return widths
}
