package main

import (
	"fmt"
	"io"
	"os"
	"runtime/debug"
	"strconv"

	"github.com/alecthomas/kong"
	"github.com/charmbracelet/x/term"
	"github.com/gurgeous/tennis"
)

var (
	Version   = ""
	CommitSHA = ""
)

type Options struct {
	Input      io.Reader    // where to read
	Output     io.Writer    // where to write
	Color      tennis.Color // auto/always/never
	Theme      tennis.Theme // auto/dark/light
	RowNumbers bool         // true if row numbers on
}

func options(ctx *MainContext) *Options {
	//
	// sha/version
	//

	if Version == "" {
		if info, ok := debug.ReadBuildInfo(); ok && info.Main.Sum != "" {
			Version = info.Main.Version
		} else {
			Version = "unknown (built from source)"
		}
	}
	const shaLen = 7
	version := fmt.Sprintf("tennis version %s", Version)
	if len(CommitSHA) >= shaLen {
		version += " (" + CommitSHA[:shaLen] + ")"
	}

	//
	// setup kong
	//

	type kongArgs struct {
		File       *os.File         `arg:"" optional:"" type:"file"`
		Color      string           `help:"Turn color off and on with auto|never|always" enum:"auto,never,always" default:"auto"`
		Theme      string           `help:"Select color theme auto|dark|light" enum:"auto,dark,light" default:"auto"`
		RowNumbers bool             `short:"n" help:"Turn on row numbers" negatable:""`
		Version    kong.VersionFlag `help:"Print the version number"`
	}

	kargs := &kongArgs{}
	kong, err := kong.New(
		kargs,
		kong.ConfigureHelp(kong.HelpOptions{Compact: true, Summary: false}),
		kong.Description("CSV pretty printer."),
		kong.Exit(ctx.Exit),
		kong.Name("tennis"),
		kong.Writers(ctx.Output, ctx.Output),
		kong.Vars{
			"version":       version,
			"versionNumber": Version,
		},
	)
	if err != nil {
		panic(err)
	}

	//
	// run kong
	//

	_, err = kong.Parse(ctx.Args)

	//
	// copy to Options
	//

	options := &Options{
		Output:     ctx.Output,
		Color:      tennis.StringToColor(kargs.Color),
		Theme:      tennis.StringToTheme(kargs.Theme),
		RowNumbers: kargs.RowNumbers,
	}

	//
	// Input
	//

	switch {
	case kargs.File != nil:
		options.Input = kargs.File
	case !isTty(ctx.Input):
		options.Input = ctx.Input
	case len(ctx.Args) > 0:
		err = fmt.Errorf("no input provided")
	}

	if err != nil || options.Input == nil {
		fmt.Println("tennis: try 'tennis --help' for more information")
		kong.FatalIfErrorf(err)
		if err == nil {
			ctx.Exit(0)
		}
		return nil // only reached in test
	}

	// success!
	return options
}

//
// tty helpers
//

func isTty(r io.Reader) bool {
	if isTtyForced() {
		return true
	}
	file, ok := r.(*os.File)
	return ok && term.IsTerminal(file.Fd())
}

func isTtyForced() bool {
	b, _ := strconv.ParseBool(os.Getenv("TTY_FORCE"))
	return b
}
