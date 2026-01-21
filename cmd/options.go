package main

import (
	"fmt"
	"io"
	"os"
	"runtime/debug"

	"github.com/alecthomas/kong"
)

//
// cli options
//

var (
	Version   = ""
	CommitSHA = ""
)

type Options struct {
	File       *os.File         `arg:"" optional:"" type:"file"`
	Color      string           `help:"Turn color off and on with auto|never|always" enum:"auto,never,always" default:"auto"`
	Theme      string           `help:"Select color theme auto|dark|light" enum:"auto,dark,light" default:"auto"`
	RowNumbers bool             `short:"n" help:"Turn on row numbers" negatable:""`
	Version    kong.VersionFlag `help:"Print the version number"`
}

func options(args []string, exit func(int), in *os.File, out io.Writer) *Options {
	// sha/version
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

	// setup kong
	options := &Options{}
	kong, err := kong.New(
		options,
		kong.ConfigureHelp(kong.HelpOptions{Compact: true, Summary: false}),
		kong.Description("CSV pretty printer."),
		kong.Exit(exit),
		kong.Name("tennis"),
		kong.Writers(out, out),
		kong.Vars{
			"version":       version,
			"versionNumber": Version,
		},
	)
	if err != nil {
		panic(err)
	}

	// parse args
	_, err = kong.Parse(args)
	if err == nil && options.File == nil {
		stat, _ := in.Stat()
		if (stat.Mode() & os.ModeCharDevice) == 0 {
			options.File = in
		} else {
			err = fmt.Errorf("no file provided")
		}
	}

	// error handler
	if err != nil {
		fmt.Fprintln(out, "tennis: try 'tennis --help' for more information")
		if len(args) == 0 {
			kong.Exit(0)
		} else {
			kong.FatalIfErrorf(err)
		}
	}

	// fmt.Printf("%# v\n", pretty.Formatter(options))
	return options
}
