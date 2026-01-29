package main

import (
	"fmt"
	"io"
	"os"
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

// os.XXX except in test
type MainContext struct {
	Args   []string
	Input  io.Reader
	Output io.Writer
	Exit   func(int)
}

func main0(ctx *MainContext) bool {
	// parse cli options
	o := NewOptions(ctx)
	if o.Closer != nil {
		defer o.Closer.Close()
	}

	// write csv
	if err := o.Table.Write(o.Input); err != nil {
		fmt.Fprintf(ctx.Output, "tennis: could not read csv - %s\n", err.Error())
		ctx.Exit(1)
	}
	return true
}
