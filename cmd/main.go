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
	"os"

	"github.com/gurgeous/tennis"
	_ "github.com/kr/pretty"
)

type MainContext struct {
	Args   []string  // os.Args (except in test)
	Stdin  *os.File  // os.Stdin (except in test)
	Stdout *os.File  // os.Stdout (except in test)
	Exit   func(int) // os.Exit (except in test)
}

func main() {
	main0(&MainContext{Args: os.Args[1:], Stdin: os.Stdin, Stdout: os.Stdout, Exit: os.Exit})
}

// broken out for testing
func main0(ctx *MainContext) {
	// parse cli options
	o := options(ctx)
	defer o.Input.Close()

	// table
	table := &tennis.Table{
		Color:      tennis.StringToColor(o.Color),
		Theme:      tennis.StringToTheme(o.Theme),
		RowNumbers: o.RowNumbers,
		Output:     ctx.Stdout,
	}
	if err := table.Write(o.Input); err != nil {
		fmt.Printf("tennis: could not read csv - %s", err.Error())
		ctx.Exit(1)
	}
}
