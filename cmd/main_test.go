package main

import (
	"testing"
)

func TestMain0(_ *testing.T) {
	// 	func main0(exitFunc func(int)) {
	// 		// parse cli options
	// 		options := options(exitFunc)
	// 		defer options.Input.Close()

	// 		// read csv
	// 		csv := csv.NewReader(options.Input)
	// 		records, err := csv.ReadAll()
	// 		if err != nil {
	// 			// REMIND: make this red?
	// 			fmt.Printf("tennis: could not read csv - %s", err.Error())
	// 			exitFunc(1)
	// 		}

	// 		// table
	// 		table := tennis.NewTable(os.Stdout)
	// 		table.Color = tennis.StringToColor(options.Color)
	// 		table.Theme = tennis.StringToTheme(options.Theme)
	// 		table.RowNumbers = options.RowNumbers
	// 		table.WriteAll(records)
	// }
}
