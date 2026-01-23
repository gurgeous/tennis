package tennis

import (
	"bufio"
	"bytes"
	"encoding/csv"
	"fmt"
	"io"
	"os"
	"reflect"
	"strings"

	"github.com/charmbracelet/colorprofile"
	"github.com/charmbracelet/lipgloss/v2"
	"github.com/jszwec/csvutil"
	"golang.org/x/term"
)

//
// types
//

type Table struct {
	Output     io.Writer // where to write
	Color      Color     // auto/always/never
	Theme      Theme     // auto/dark/light
	TermWidth  int       // terminal width or 0 to autodetect
	RowNumbers bool      // true if row numbers on
	Title      string    // pretty title at the top of the table
	ctx        context   // internal state
}

// internal context
type context struct {
	w          *bufio.Writer        // bufio wrapper around forward
	headers    []string             // first row of records
	records    [][]string           // all records (including headers)
	dataWidths []int                // width of raw data
	layout     []int                // width of each column in terminal
	profile    colorprofile.Profile // ascii/ansi256/truecolor/etc
	styles     *styles              // colors
	buf        strings.Builder      // re-usable scratch buffer
	pipe       string               // stylized pipe character
}

//
// WriteXXX
//

// write entire csv file
func (t *Table) Write(r io.Reader) error {
	return t.WriteCsv(csv.NewReader(r))
}

// write entire csv reader
func (t *Table) WriteCsv(r *csv.Reader) error {
	records, err := r.ReadAll()
	if err != nil {
		return fmt.Errorf("failed to read csv: %w", err)
	}
	t.WriteRecords(records)
	return nil
}

// write all structs (must be the same type)
func (t *Table) WriteStructs(records any) error {
	// bit o' sanity checking
	val := reflect.ValueOf(records)
	// fmt.Printf("val=%v\n", val)
	// fmt.Printf("kind=%v\n", val.Kind())
	// fmt.Printf("type=%v\n", val.Type())
	// fmt.Printf("elem=%v\n", val.Type().Elem())

	if val.Kind() != reflect.Slice && val.Kind() != reflect.Array {
		return fmt.Errorf("must be an array/slice of structs, not %v", val)
	}

	// more sanity
	// if walkType(val.Type().Elem()).Kind() != reflect.Struct {

	// struct must have at least one public member!
	// all structs must be the same type
	// for ii := range val.Len() {
	// 	x := val.Index(ii)
	// 	fmt.Printf("val[%d]=%v\n", ii, x)
	// }
	// 	if err := e.encodeStruct(walkValue(v.Index(i))); err != nil {
	// 		return err
	// 	}
	// }

	b, err := csvutil.Marshal(records)
	// fmt.Printf("bytyes = '%v'\n", string(b))
	if err != nil {
		return fmt.Errorf("failed to marshal structs: %w", err)
	}
	return t.Write(bytes.NewReader(b))
}

// write all records
func (t *Table) WriteRecords(records [][]string) {
	// edge cases
	if len(records) == 0 || len(records[0]) == 0 {
		return
	}

	// fixup ragged
	nFields := len(records[0])
	for ii, record := range records {
		if len(record) == nFields {
			continue
		}
		if len(record) < nFields {
			for j := len(record); j < nFields; j++ {
				records[ii] = append(records[ii], "")
			}
		} else if len(record) > nFields {
			records[ii] = records[ii][:nFields]
		}
	}
	t.ctx.records = records
	t.ctx.headers = records[0]

	// setup
	t.setup()
	defer func() { t.ctx = context{} }()

	//
	// layout
	//

	t.ctx.dataWidths = t.constructDataWidths()
	t.ctx.layout = constructLayout(t.ctx.dataWidths, t.TermWidth)
	if len(os.Getenv("TENNIS_DEBUG")) != 0 {
		t.debug()
	}

	//
	// render
	//

	t.render()
}

func (t *Table) setup() {
	// output
	if t.Output == nil {
		t.Output = os.Stdout
	}
	t.ctx.w = bufio.NewWriter(t.Output)

	// profile
	switch t.Color {
	case ColorAuto:
		t.ctx.profile = colorprofile.Detect(t.Output, os.Environ())
	case ColorAlways:
		t.ctx.profile = colorprofile.TrueColor
	case ColorNever:
		t.ctx.profile = colorprofile.Ascii
	}

	// termwidth
	if t.TermWidth == 0 {
		const defaultTermWidth = 80
		termwidth, _, err := term.GetSize(int(os.Stdout.Fd()))
		if err != nil {
			t.TermWidth = defaultTermWidth
		} else {
			t.TermWidth = termwidth
		}
	}

	// theme
	if t.Theme == ThemeAuto && t.Color != ColorNever {
		if lipgloss.HasDarkBackground(os.Stdin, os.Stderr) {
			t.Theme = ThemeDark
		} else {
			t.Theme = ThemeLight
		}
	}

	// styles
	t.ctx.styles = constructStyles(t.ctx.profile, t.Theme)
}

func (t *Table) debug() {
	debugf := func(format string, args ...any) {
		str := fmt.Sprintf(format, args...)
		fmt.Fprintf(os.Stderr, "\033[1;37;42m[tennis]\033[0m %s\n", str)
	}

	debugf("shape [%dx%d]", len(t.ctx.records[0]), len(t.ctx.records))
	debugf("termwidth = %d", t.TermWidth)
	keys := []string{"NO_COLOR", "CLICOLOR_FORCE", "TTY_FORCE"}
	for _, key := range keys {
		debugf("$%-14s = '%s'", key, os.Getenv(key))
	}
	debugf("color=%v, theme=%v, profile=%v", t.Color, t.Theme, t.ctx.profile)
	debugf("dataWidths = %v", t.ctx.dataWidths)
	debugf("layout     = %v", t.ctx.layout)
}

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
