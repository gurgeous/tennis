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

func main() {
	ctx := &MainContext{
		Args:   os.Args[1:],
		Input:  os.Stdin,
		Output: os.Stdout,
		Exit:   os.Exit,
	}
	_ = main0(ctx)
	defer os.Stdin.Close()
}

//
// broken out for testing
//

// os.XXX except in test
type MainContext struct {
	Args   []string
	Input  io.Reader
	Output io.Writer
	Exit   func(int)
}

func main0(ctx *MainContext) bool {
	// parse cli options
	o := options(ctx)

	// table
	table := &tennis.Table{
		Color:      o.Color,
		Output:     o.Output,
		RowNumbers: o.RowNumbers,
		Theme:      o.Theme,
	}

	// write csv
	if err := table.Write(o.Input); err != nil {
		fmt.Printf("tennis: could not read csv - %s", err.Error())
		ctx.Exit(1)
	}
	return true
}
