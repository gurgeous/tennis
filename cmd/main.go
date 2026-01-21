package main

//
// TODO
// tests
// version stuff
// goreleaser
// https://github.com/antgroup/hugescm/blob/e47f394bbfe9ab56b1df2f2745b00755dfc52d3b/pkg/kong/mapper.go#L630
//

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
	File       *os.File         `arg:"" type:"file"`
	Color      string           `help:"Turn color off and on with auto|never|always" enum:"auto,never,always" default:"auto"`
	Theme      string           `help:"Select color theme auto|dark|light" enum:"auto,dark,light" default:"auto"`
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
	// file, err := os.Open(options.File)
	// if err != nil {
	// 	fatal("error opening file", err)
	// }
	file := options.File
	defer file.Close()

	// read csv
	csv := csv.NewReader(file)
	records, err := csv.ReadAll()
	if err != nil {
		fatal("error opening file", err)
	}

	// table
	table := tennis.NewTable(os.Stdout)
	table.Color = tennis.StringToColor(options.Color)
	table.Theme = tennis.StringToTheme(options.Theme)
	table.RowNumbers = options.RowNumbers
	table.WriteAll(records)
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

	// automatically do the "-" thing
	args := make([]string, len(os.Args)-1)
	copy(args, os.Args[1:])
	if len(args) == 0 {
		stat, _ := os.Stdin.Stat()
		if (stat.Mode() & os.ModeCharDevice) == 0 {
			args = append(args, "-")
		}
	}

	// parse args
	_, err = kong.Parse(args)
	if err != nil {
		fmt.Printf("%:v\n", err)
	}

	if err != nil {
		fmt.Println("tennis: try 'tennis --help' for more information")
		if len(args) == 0 {
			os.Exit(0)
		}
		kong.FatalIfErrorf(err)
	}

	return options
}
