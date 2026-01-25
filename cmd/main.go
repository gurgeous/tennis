package main

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
		fmt.Printf("tennis: could not read csv - %s\n", err.Error())
		ctx.Exit(1)
	}
	return true
}
