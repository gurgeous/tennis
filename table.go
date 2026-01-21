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

//go:generate stringer -type=Color -trimprefix=Color
const (
	ColorAuto Color = iota
	ColorAlways
	ColorNever
)

func StringToColor(str string) Color {
	for i := ColorAuto; i <= ColorNever; i++ {
		if strings.EqualFold(str, i.String()) {
			return i
		}
	}
	return ColorAuto
}

type Theme int

//go:generate stringer -type=Theme -trimprefix=Theme
const (
	ThemeAuto Theme = iota
	ThemeDark
	ThemeLight
)

func StringToTheme(str string) Theme {
	for i := ThemeAuto; i <= ThemeLight; i++ {
		if strings.EqualFold(str, i.String()) {
			return i
		}
	}
	return ThemeAuto
}

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

func (t *Table) WriteAll(records [][]string) {
	//
	// edge cases
	//

	t.records = records
	if len(t.records) == 0 {
		return
	}
	t.headers = records[0]
	if len(t.headers) == 0 {
		return
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
	t.render()
}
