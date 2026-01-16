package main

// https://github.com/charmbracelet/meta
// rivo/uniseg
// goreleaser?

// https://github.com/uber-go/fx/blob/master/Makefile
// https://github.com/antonmedv/fx/blob/master/scripts/build.mjs

import (
	"fmt"
	"os"
	"runtime/debug"

	"github.com/alecthomas/kong"
)

var (
	Version   = ""
	CommitSHA = ""
)

type Options struct {
	File    string           `arg:"" type:"existingfile"`
	Version kong.VersionFlag `short:"v" help:"Print the version number"`
}

func main() {
	//
	// version
	//

	if Version == "" {
		if info, ok := debug.ReadBuildInfo(); ok && info.Main.Sum != "" {
			Version = info.Main.Version
		} else {
			Version = "unknown (built from source)"
		}
	}
	const shaLen = 7
	version := fmt.Sprintf("gum version %s", Version)
	if len(CommitSHA) >= shaLen {
		version += " (" + CommitSHA[:shaLen] + ")"
	}

	//
	// args
	//

	args := &Options{}
	kong, err := kong.New(
		args,
		kong.ConfigureHelp(kong.HelpOptions{Compact: true, Summary: false}),
		kong.Description("CSV pretty printer."),
		kong.Vars{
			"version":       version,
			"versionNumber": Version,
		},
	)
	if err != nil {
		panic(err)
	}
	_, err = kong.Parse(os.Args[1:])
	if err != nil {
		fmt.Println("tennis: try 'tennis --help' for more information")
		if len(os.Args) == 1 {
			os.Exit(0)
		}
		kong.FatalIfErrorf(err)
	}

	Tennis(args)
}
