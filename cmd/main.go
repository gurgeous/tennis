package main

//
// TODO
// tests
// - graphemes
// - goreleaser & sha/version
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
	"os"

	"github.com/gurgeous/tennis"
)

func main() {
	// parse cli options
	options := options(os.Args[1:], os.Exit)
	defer options.File.Close()

	// read csv
	csv := csv.NewReader(options.File)
	records, err := csv.ReadAll()
	if err != nil {
		fatal("error opening file", err)
	}

	// table
	table := tennis.NewTable(os.Stdout)
	table.Color = tennis.StringToColor(options.Color)
	table.Theme = tennis.StringToTheme(options.Theme)
	table.RowNumbers = options.RowNumbers
	table.WriteAll(records)
}
