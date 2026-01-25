package main

import (
	"context"
	"fmt"
	"io"
	"os"
	"runtime/debug"
	"strconv"

	"github.com/charmbracelet/x/term"
	"github.com/gurgeous/tennis"
	"github.com/urfave/cli/v3"
)

// see .goreleaser.yaml
var Version = ""

type Options struct {
	Table tennis.Table // a configured table
	Input io.Reader    // where to read
}

func options(ctx *MainContext) *Options {
	if Version == "" {
		if info, ok := debug.ReadBuildInfo(); ok && info.Main.Sum != "" {
			Version = info.Main.Version
		} else {
			Version = "unknown (built from source)"
		}
	}

	var (
		fileArg     string
		colorValue  string
		themeValue  string
		rowNumbers  bool
		title       string
		showVersion bool
	)

	cmd := &cli.Command{
		Name:                  "tennis",
		Usage:                 "CSV pretty printer.",
		ArgsUsage:             "[file]",
		Version:               fmt.Sprintf("tennis version %s", Version),
		Reader:                ctx.Input,
		Writer:                ctx.Output,
		ErrWriter:             ctx.Output,
		HideHelpCommand:       true,
		HideVersion:           true,
		EnableShellCompletion: false,
		Flags: []cli.Flag{
			&cli.StringFlag{
				Name:  "color",
				Usage: "Turn color off and on with auto|never|always",
				Value: "auto",
			},
			&cli.StringFlag{
				Name:  "theme",
				Usage: "Select color theme auto|dark|light",
				Value: "auto",
			},
			&cli.BoolFlag{
				Name:    "row-numbers",
				Aliases: []string{"n"},
				Usage:   "Turn on row numbers",
			},
			&cli.StringFlag{
				Name:    "title",
				Aliases: []string{"t"},
				Usage:   "Add a pretty title at the top",
			},
			&cli.BoolFlag{
				Name:  "version",
				Usage: "Print the version number",
			},
		},
		Action: func(ctx context.Context, cmd *cli.Command) error {
			if cmd.Bool("version") {
				showVersion = true
				fmt.Fprintf(cmd.Writer, "tennis version %s\n", Version)
				return nil
			}
			if cmd.Args().Len() > 1 {
				return fmt.Errorf("unexpected argument %s", cmd.Args().Get(1))
			}
			fileArg = cmd.Args().First()
			colorValue = cmd.String("color")
			themeValue = cmd.String("theme")
			rowNumbers = cmd.Bool("row-numbers")
			title = cmd.String("title")
			return nil
		},
		ExitErrHandler: func(context.Context, *cli.Command, error) {},
	}

	if err := cmd.Run(context.Background(), append([]string{"tennis"}, ctx.Args...)); err != nil {
		fmt.Fprintln(ctx.Output, "tennis: try 'tennis --help' for more information")
		ctx.Exit(1)
		return nil
	}
	if showVersion {
		ctx.Exit(0)
		return nil
	}

	options := &Options{
		Table: tennis.Table{
			Color:      tennis.StringToColor(colorValue),
			Output:     ctx.Output,
			RowNumbers: rowNumbers,
			Theme:      tennis.StringToTheme(themeValue),
			Title:      title,
		},
	}

	//
	// set Input, but only if we don't have a kargs error yet
	//

	switch {
	case fileArg != "" && fileArg != "-":
		// tennis something.csv
		file, err := os.Open(fileArg)
		if err != nil {
			fmt.Fprintln(ctx.Output, "tennis: try 'tennis --help' for more information")
			ctx.Exit(1)
			return nil
		}
		options.Input = file
	case fileArg == "-" || !isTty(ctx.Input):
		// cat something.csv | tennis OR tennis -
		options.Input = ctx.Input
	case len(ctx.Args) > 0:
		// no input but we got some args, busted
		fmt.Fprintln(ctx.Output, "tennis: try 'tennis --help' for more information")
		ctx.Exit(1)
		return nil
	}

	if options.Input == nil {
		fmt.Fprintln(ctx.Output, "tennis: try 'tennis --help' for more information")
		ctx.Exit(0)
		return nil // only reached in test
	}

	// success!
	return options
}

//
// helpers
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
