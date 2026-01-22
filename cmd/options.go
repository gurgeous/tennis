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

	options := &Options{}
	kong, err := kong.New(
		options,
		kong.ConfigureHelp(kong.HelpOptions{Compact: true, Summary: false}),
		kong.Description("CSV pretty printer."),
		kong.Exit(ctx.Exit),
		kong.Name("tennis"),
		kong.Writers(ctx.Stdout, ctx.Stdout),
		kong.Vars{
			"version":       version,
			"versionNumber": Version,
		},
		kong.WithAfterApply(func(kong *kong.Kong) error {
			if options.Input == nil {
				options.Input = stdinInput(ctx.Stdin)
				if options.Input == nil && len(ctx.Args) > 0 {
					return fmt.Errorf("no input provided")
				}
			}
			return nil
		}),
	)
	if err != nil {
		panic(err)
	}

	//
	// run kong
	//

	_, err = kong.Parse(ctx.Args)
	if err != nil || options.Input == nil {
		fmt.Println("tennis: try 'tennis --help' for more information")
		if err == nil {
			// running naked, this is fine
			kong.Exit(0)
		} else {
			kong.FatalIfErrorf(err)
		}
		return nil // only reached in test
	}

	//
	// success!
	//

	return options
}

func isTTYForced() bool {
	b, _ := strconv.ParseBool(os.Getenv("TTY_FORCE"))
	return b
}

func stdinInput(stdin *os.File) *os.File {
	// we don't have a file. can we use stdin?
	isTty := isTTYForced() || term.IsTerminal(stdin.Fd())
	if !isTty {
		// seems to be a file, go for it
		return stdin
	}
	return nil // fmt.Errorf("no file provided")
}
