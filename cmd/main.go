package main

import (
	"encoding/csv"
	"fmt"
	"os"
	"runtime/debug"

	"github.com/alecthomas/kong"
	"github.com/gurgeous/tennis"
)

//
// cli options
//

var (
	Version   = ""
	CommitSHA = ""
)

type Options struct {
	File       string           `arg:"" type:"existingfile"`
	Color      string           `help:"Set color to auto|never|always" enum:"auto,never,always" default:"auto"`
	RowNumbers bool             `short:"n" help:"Turn on row numbers" negatable:""`
	Version    kong.VersionFlag `help:"Print the version number"`
}

//
// main
//

func main() {
	// parse cli options
	options := options()

	// open file
	file, err := os.Open(options.File)
	if err != nil {
		fatal("error opening file", err)
	}
	defer file.Close()

	// read csv
	csv := csv.NewReader(file)
	records, err := csv.ReadAll()
	if err != nil {
		fatal("error opening file", err)
	}

	// table
	table := tennis.NewTable(os.Stdout)
	if options.RowNumbers {
		table.RowNumbers = true
	}
	if err := table.WriteAll(records); err != nil {
		fatal("table error", err)
	}
}

func options() *Options {
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
		kong.Vars{
			"version":       version,
			"versionNumber": Version,
		},
	)
	if err != nil {
		panic(err)
	}

	// parse args
	_, err = kong.Parse(os.Args[1:])
	if err != nil {
		fmt.Println("tennis: try 'tennis --help' for more information")
		if len(os.Args) == 1 {
			os.Exit(0)
		}
		kong.FatalIfErrorf(err)
	}

	return options
}
