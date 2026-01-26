package main

import (
	"context"
	"fmt"
	"io"
	"os"
	"runtime/debug"
	"slices"
	"strconv"

	"github.com/charmbracelet/x/term"
	"github.com/gurgeous/tennis"
	"github.com/k0kubun/pp/v3"
	"github.com/urfave/cli/v3"
)

// see .goreleaser.yaml
var Version = ""

type Options struct {
	Table tennis.Table // a configured table
	Input io.Reader    // where to read
}

func options(ctx *MainContext) *Options {
	const banner = "tennis: try 'tennis --help' for more information"

	if Version == "" {
		if info, ok := debug.ReadBuildInfo(); ok && info.Main.Sum != "" {
			Version = info.Main.Version
		} else {
			Version = "unknown (built from source)"
		}
	}

	cmd := &cli.Command{
		Name:                  "tennis",
		Usage:                 "Stylish CSV tables in your terminal.",
		ArgsUsage:             "[file.csv]",
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
				Validator: func(value string) error {
					return isOneOf(value, "auto", "never", "always")
				},
			},
			&cli.StringFlag{
				Name:  "theme",
				Usage: "Select color theme auto|dark|light",
				Value: "auto",
				Validator: func(value string) error {
					return isOneOf(value, "auto", "dark", "light")
				},
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
		OnUsageError: func(_ctx context.Context, cmd *cli.Command, err error, isSubcommand bool) error {
			// override to avoid the (ugly) default error handling
			fmt.Fprintf(ctx.Output, "tennis: %s\n", err.Error())
			fmt.Fprintln(ctx.Output, banner)
			return err
		},
		Action: func(_ context.Context, cmd *cli.Command) error {
			// override to avoid showing help by default
			return nil
		},
		ExitErrHandler: func(_ context.Context, _ *cli.Command, err error) {
			// overridden to avoid call to os.Exit
		},
	}

	err := cmd.Run(context.Background(), append([]string{"tennis"}, ctx.Args...))
	fmt.Printf("BELOW err=%v", err)
	pp.Println(cmd)
	if err != nil {
		ctx.Exit(1)
		return nil // only when running in test
	}

	// what happens here?

	if cmd.Bool("version") {
		ctx.Exit(0)
		return nil
	}

	//
	// populate options
	//

	options := &Options{
		Table: tennis.Table{
			Color:      tennis.StringToColor(cmd.String("color")),
			Output:     ctx.Output,
			RowNumbers: cmd.Bool("row-numbers"),
			Theme:      tennis.StringToTheme(cmd.String("theme")),
			Title:      cmd.String("title"),
		},
	}

	//
	// set Input, but only if we don't have a kargs error yet
	//

	fileArg := cmd.Args().First()
	switch {
	case fileArg != "" && fileArg != "-":
		// tennis something.csv
		file, err := os.Open(fileArg)
		if err != nil {
			fmt.Fprintln(ctx.Output, banner)
			ctx.Exit(1)
			return nil
		}
		options.Input = file
	case fileArg == "-" || !isTty(ctx.Input):
		// cat something.csv | tennis OR tennis -
		options.Input = ctx.Input
	case len(ctx.Args) > 0:
		// no input but we got some args, busted
		fmt.Fprintln(ctx.Output, banner)
		ctx.Exit(1)
		return nil
	}

	if options.Input == nil {
		fmt.Fprintln(ctx.Output, banner)
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

func isOneOf(value string, allowed ...string) error {
	if slices.Contains(allowed, value) {
		return nil
	}
	return fmt.Errorf("must be one of %v", allowed)
}

// err = cmd.OnUsageError(ctx, cmd, err, cmd.parent != nil)
// 			err = cmd.handleExitCoder(ctx, err)
// 			return ctx, err
