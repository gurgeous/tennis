package main

//
// TODO
// - features
//   - write array of structs? (https://github.com/jszwec/csvutil)
// - tests
//   - style/downsample
//   - jagged
// - releaser
//   - goreleaser & sha/version
//   - see ~/sync/vectrogo/justfile for goreleaser
//   - README/LICENSE
//   - demo.gif
//   - https://github.com/antonmedv/fx/blob/master/scripts/build.mjs
//   - https://github.com/charmbracelet/meta
//   - https://github.com/uber-go/fx/blob/master/Makefile
//

import (
	"fmt"
	"io"
	"os"

	_ "github.com/k0kubun/pp/v3"
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

	// write csv
	if err := o.Table.Write(o.Input); err != nil {
		fmt.Printf("tennis: could not read csv - %s", err.Error())
		ctx.Exit(1)
	}
	return true
}
