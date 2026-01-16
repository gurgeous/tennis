package main

// TODO
//
// - make cli flags work
// - graphemes
// - feature: row numbers
// - feature: placeholders
// - tests
// - benchmarks/fit/slow/etc. (repeat? graphemes?)
// - extract lib?
//   - https://ieftimov.com/posts/golang-package-multiple-binaries/
//
//
// goreleaser?
// https://github.com/charmbracelet/meta
// https://github.com/uber-go/fx/blob/master/Makefile
// https://github.com/antonmedv/fx/blob/master/scripts/build.mjs
// https://github.com/charmbracelet/lipgloss/blob/f2d1864a58cd455ca118e04123feae177d7d2eef/style.go
//

import (
	"fmt"
	"os"
	"runtime/debug"

	"github.com/alecthomas/kong"
	"github.com/charmbracelet/lipgloss"
	"github.com/muesli/termenv"
)

var (
	Version   = ""
	CommitSHA = ""
)

type Options struct {
	File         string           `arg:"" type:"existingfile"`
	Color        string           `help:"Set color to never, always or auto" enum:"never,auto,always" default:"auto"`
	Placeholders bool             `help:"Turn on/off placeholders for empty cells" negatable:"" default:"true"`
	RowNumbers   bool             `help:"Turn on row numbers" negatable:""`
	Zebra        bool             `help:"Turn on/off zebra stripes" negatable:""`
	Version      kong.VersionFlag `short:"v" help:"Print the version number"`
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
	version := fmt.Sprintf("tennis version %s", Version)
	if len(CommitSHA) >= shaLen {
		version += " (" + CommitSHA[:shaLen] + ")"
	}

	//
	// args
	//

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
	_, err = kong.Parse(os.Args[1:])
	if err != nil {
		fmt.Println("tennis: try 'tennis --help' for more information")
		if len(os.Args) == 1 {
			os.Exit(0)
		}
		kong.FatalIfErrorf(err)
	}

	// --color
	// https://github.com/charmbracelet/lipgloss/issues/445
	switch options.Color {
	case "never":
		os.Setenv("NO_COLOR", "1")
		os.Unsetenv("CLICOLOR")
		os.Unsetenv("CLICOLOR_FORCE")
	case "always":
		os.Unsetenv("NO_COLOR")
		os.Unsetenv("CLICOLOR")
		os.Setenv("CLICOLOR_FORCE", "1")
	}
	if force := os.Getenv("CLICOLOR_FORCE"); force != "" && force != "0" {
		lipgloss.DefaultRenderer().SetColorProfile(termenv.TrueColor)
	}

	// go
	Tennis(options)
}
