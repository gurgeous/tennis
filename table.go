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
	ctx        context
}

// internal context
type context struct {
	w       *bufio.Writer
	headers []string
	records [][]string
	layout  []int
	profile colorprofile.Profile
	styles  *styles
	buf     strings.Builder
	pipe    string
}

const (
	defaultTermWidth = 80
)

//
// Color
//

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

//
// Theme
//

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

	t.ctx.records = records
	if len(t.ctx.records) == 0 {
		return
	}
	t.ctx.headers = records[0]
	if len(t.ctx.headers) == 0 {
		return
	}

	//
	// setup styles
	//

	t.ctx.w = bufio.NewWriter(t.Forward)
	switch t.Color {
	case ColorAuto:
		t.ctx.profile = colorprofile.Detect(t.Forward, os.Environ())
	case ColorAlways:
		t.ctx.profile = colorprofile.TrueColor
	case ColorNever:
		t.ctx.profile = colorprofile.Ascii
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
	t.ctx.styles = constructStyles(t.ctx.profile, t.Theme)

	//
	// layout
	//

	dataWidths := t.measureDataWidths()
	t.ctx.layout = constructLayout(dataWidths, t.TermWidth)

	//
	// render
	//

	t.render()
}
