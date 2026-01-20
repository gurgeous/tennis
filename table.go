package tennis

import "encoding/csv"

//
// initial features
// - autolayout
// - colors/themes
// - print tables
// - separators
// - placeholders
// - row numbers
//
// exhaustive list of features
// - color scales
// - digits for formatting floats
// - layout:true/false/hardcoded
// - mark rows
// - override header names
// - save CSV
// - search cells
// - separators
// - theme selection
// - title
// - titleize column headers
// - turning color off/on
// - type coercion
// - zebra
//
// go get charm.land/bubbletea/v2
// go get charm.land/bubbles/v2
// go get charm.land/lipgloss/v2
//
// compat.HasDarkBackground = lipgloss.HasDarkBackground(os.Stdin, os.Stderr)
// compat.Profile = colorprofile.Detect(os.Stderr, os.Environ())
//
// s := someStyle.Render("Fancy Lip Gloss Output")
// // Before
// fmt.Println(s)
// // After
// lipgloss.Println(s)
//
//// Detect the background color. Notice we're writing to stderr.
// hasDarkBG, err := lipgloss.HasDarkBackground(os.Stdin, os.Stderr)
// if err != nil {
//     log.Fatal("Oof:", err)
// }
//
// // Create a helper for choosing the appropriate color.
// lightDark := lipgloss.LightDark(hasDarkBG)
//
// // Declare some colors.
// thisColor := lightDark("#C5ADF9", "#864EFF")
// thatColor := lightDark("#37CD96", "#22C78A")
//
// // Render some styles.
// a := lipgloss.NewStyle().Foreground(thisColor).Render("this")
// b := lipgloss.NewStyle().Foreground(thatColor).Render("that")
//
// // Print to stderr.
// lipgloss.Fprintf(os.Stderr, "my fave colors are %s and %s...for now.", a, b)
//

// - autolayout
// - colors/themes
// - print tables
// - separators
// - placeholders
// - row numbers

type Table struct {
	// config
	Color      Color
	Theme      Theme
	RowNumbers bool

	// internal stuff
	r       *csv.Reader
	headers []string
	rows    [][]string
	layout  []int
	widths  []int
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

func NewTable(r *csv.Reader) *Table {
	return &Table{r: r}
}

// func Tennis(opts *Options) {
// 	table := &Table{opts: opts}

// 	// open file
// 	file, err := os.Open(opts.File)
// 	if err != nil {
// 		Fatal("error opening file", err)
// 	}
// 	defer file.Close()

// 	// read CSV
// 	table.csv = csv.NewReader(file)
// 	table.rows, err = table.csv.ReadAll()
// 	if err != nil {
// 		Fatal("error reading CSV", err)
// 	}

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
