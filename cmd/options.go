package main

import (
	"fmt"
	"os"
	"runtime/debug"
	"strconv"

	"github.com/alecthomas/kong"
	"github.com/charmbracelet/x/term"
)

//
// cli options
//

const (
	banner = "tennis: try 'tennis --help' for more information"
)

var (
	Version   = ""
	CommitSHA = ""
)

// Output     *os.File         `short:"o" help:"Write output to this file." type:"file"`
type Options struct {
	Input      *os.File         `arg:"" optional:"" type:"file"`
	Color      string           `help:"Turn color off and on with auto|never|always" enum:"auto,never,always" default:"auto"`
	Theme      string           `help:"Select color theme auto|dark|light" enum:"auto,dark,light" default:"auto"`
	RowNumbers bool             `short:"n" help:"Turn on row numbers" negatable:""`
	Version    kong.VersionFlag `help:"Print the version number"`
}

// REMIND add more helpers and stop using "capture", use something else for tests

func options(exitFunc func(int)) *Options {
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

	//
	// setup kong
	//

	options := &Options{}
	kong, err := kong.New(
		options,
		kong.ConfigureHelp(kong.HelpOptions{Compact: true, Summary: false}),
		kong.Description("CSV pretty printer."),
		kong.Exit(exitFunc),
		kong.Name("tennis"),
		kong.Writers(os.Stdout, os.Stdout),
		kong.Vars{
			"version":       version,
			"versionNumber": Version,
		},
	)
	if err != nil {
		panic(err)
	}

	// run kong
	_, err = kong.Parse(os.Args[1:])
	if err != nil {
		fmt.Println(banner)
		kong.FatalIfErrorf(err)
		return options
	}

	//
	// post-process
	//

	if err == nil && options.Input == nil {
		// we don't have a file. can we use stdin?
		stdinIsTty := isTTYForced() || term.IsTerminal(os.Stdin.Fd())
		if !stdinIsTty {
			options.Input = os.Stdin
		} else {
			if len(os.Args) == 1 {
				// special case: they just ran the thing naked
				fmt.Println(banner)
				kong.Exit(0)
			} else {
				err = fmt.Errorf("no file provided")
			}
		}
	}

	// error handler
	if err != nil {
		fmt.Println(banner)
		kong.FatalIfErrorf(err)
	}

	return options
}

func isTTYForced() bool {
	b, _ := strconv.ParseBool(os.Getenv("TTY_FORCE"))
	return b
}
