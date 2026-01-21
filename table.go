package tennis

import (
	"bufio"
	"io"
	"os"
	"strings"

	"github.com/charmbracelet/colorprofile"
	"github.com/charmbracelet/lipgloss/v2"
	"golang.org/x/term"
)

//
// TODO
// main
// tests
// env variables?
//

//
// types
//

type Table struct {
	Color      Color
	Forward    io.Writer
	TermWidth  int
	Theme      Theme
	RowNumbers bool
	// internal
	w       *bufio.Writer
	headers []string
	records [][]string
	layout  []int
	profile colorprofile.Profile
	styles  *styles
	buf     strings.Builder
	pipe    string
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
	defaultTermWidth = 80
	minFieldWidth    = 2
)

//
// public
//

func NewTable(w io.Writer) *Table {
	return &Table{Forward: w}
}

func (t *Table) WriteAll(records [][]string) error {
	//
	// edge cases
	//

	t.records = records
	if len(t.records) == 0 {
		return nil
	}
	t.headers = records[0]
	if len(t.headers) == 0 {
		return nil
	}

	//
	// setup styles
	//

	t.w = bufio.NewWriter(t.Forward)
	t.profile = colorprofile.Detect(t.Forward, os.Environ())
	switch t.Color {
	case ColorAuto:
		if t.profile >= colorprofile.ANSI256 {
			t.Color = ColorAlways
		} else {
			t.Color = ColorNever
		}
	case ColorAlways:
		t.profile = colorprofile.TrueColor
	case ColorNever:
		t.profile = colorprofile.Ascii
	}

	if t.TermWidth == 0 {
		termwidth, _, err := term.GetSize(int(os.Stdout.Fd()))
		if err != nil {
			t.TermWidth = defaultTermWidth
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
	t.styles = t.constructStyles()

	//
	// render
	//

	t.layout = t.constructLayout()
	if err := t.render(); err != nil {
		return err
	}

	return nil
}
