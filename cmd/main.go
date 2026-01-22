package main

//
// TODO
// tests
// - graphemes
// - goreleaser & sha/version
// - see ~/sync/vectrogo/justfile for goreleaser
// - README/LICENSE
// - demo.gif
// future - zebra, benchmarks, layout false,true, color scales, coerce/format numberics
// future - mark/search, save csv, header names, titleize, themes
//
// https://github.com/antonmedv/fx/blob/master/scripts/build.mjs
// https://github.com/charmbracelet/meta
// https://github.com/uber-go/fx/blob/master/Makefile
//

import (
	"encoding/csv"
	"fmt"
	"os"

	"github.com/gurgeous/tennis"
)

func main() {
	main0(os.Exit)
}

// broken out for testing
func main0(exitFunc func(int)) {
	// parse cli options
	options := options(exitFunc)
	defer options.Input.Close()

	// read csv
	csv := csv.NewReader(options.Input)
	records, err := csv.ReadAll()
	if err != nil {
		// REMIND: make this red?
		fmt.Printf("tennis: could not read csv - %s", err.Error())
		exitFunc(1)
	}

	// table
	table := tennis.NewTable(os.Stdout)
	table.Color = tennis.StringToColor(options.Color)
	table.Theme = tennis.StringToTheme(options.Theme)
	table.RowNumbers = options.RowNumbers
	table.WriteAll(records)
}
