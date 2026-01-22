package main

//
// TODO
// tests
// - --output
// - graphemes
// - goreleaser & sha/version
// - see ~/sync/vectrogo/justfile for goreleaser
// - README/LICENSE
// - demo.gif
// - run with array of structs?
// future - zebra, benchmarks, layout false,true, color scales, coerce/format numberics
// future - mark/search, save csv, header names, titleize, themes
//
// https://github.com/antonmedv/fx/blob/master/scripts/build.mjs
// https://github.com/charmbracelet/meta
// https://github.com/uber-go/fx/blob/master/Makefile
//

import (
	"fmt"
	"io"
	"os"

	"github.com/gurgeous/tennis"
	_ "github.com/kr/pretty"
)

type MainContext struct {
	Args   []string  // os.Args (except in test)
	Input  io.Reader // os.Stdin (except in test)
	Output io.Writer // os.Stdout (except in test)
	Exit   func(int) // os.Exit (except in test)
}

func main() {
	main0(&MainContext{
		Args:   os.Args[1:],
		Input:  os.Stdin,
		Output: os.Stdout,
		Exit:   os.Exit,
	})
	defer os.Stdin.Close()
}

// broken out for testing
func main0(ctx *MainContext) {
	// parse cli options
	o := options(ctx)

	// table
	table := &tennis.Table{
		Color:      o.Color,
		Theme:      o.Theme,
		RowNumbers: o.RowNumbers,
		Output:     ctx.Output,
	}

	// write csv
	if err := table.Write(o.Input); err != nil {
		fmt.Printf("tennis: could not read csv - %s", err.Error())
		ctx.Exit(1)
	}
}
