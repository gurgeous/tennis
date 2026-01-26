package main

import (
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"runtime/debug"
	"slices"
	"strconv"

	"github.com/charmbracelet/x/term"
	"github.com/gurgeous/tennis"
	_ "github.com/k0kubun/pp/v3"
	"github.com/urfave/cli/v3"
)

// set by goreleaser
var Version = ""

type Options struct {
	Table tennis.Table // a configured table
	Input io.Reader    // where to read
}

const banner = "tennis: try 'tennis --help' for more information"

// wrapper around options0, for handling errors and calling ctx.Exit
func options(ctx *MainContext) *Options {
	opts, err := options0(ctx)
	if opts == nil {
		if err != nil {
			fmt.Fprintf(ctx.Output, "tennis: %s\n", err.Error())
			fmt.Fprintln(ctx.Output, banner)
			ctx.Exit(1)
		} else {
			ctx.Exit(0)
		}
		return nil // only reached during tests
	}
	return opts
}

func options0(ctx *MainContext) (*Options, error) {
	// handle the naked case early for simplicity
	if len(ctx.Args) == 0 && isTty(ctx.Input) {
		fmt.Fprintln(ctx.Output, banner)
		return nil, nil
	}

	// calculate version
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
		Version:               Version,
		Reader:                ctx.Input,
		Writer:                ctx.Output,
		ErrWriter:             ctx.Output,
		EnableShellCompletion: true,
		HideHelpCommand:       true,
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
		},

		// overridden (as nop) to avoid default behavior that we don't care for
		Action:         func(_ context.Context, _ *cli.Command) error { return nil },
		ExitErrHandler: func(_ context.Context, _ *cli.Command, _ error) {},
		OnUsageError:   func(_ context.Context, _ *cli.Command, err error, _ bool) error { return err },
	}

	//
	// parse args
	//

	args := append([]string{"tennis"}, ctx.Args...)
	if err := cmd.Run(context.Background(), args); err != nil {
		return nil, err //nolint:wrapcheck
	}
	// fmt.Printf("after run %v\n", err)
	// pp.Println(cmd)

	// --help/--version
	if cmd.Bool("version") || cmd.Bool("help") {
		return nil, nil // only reached during tests
	}

	// open the file
	input, err := getInput(ctx, cmd)
	if err != nil {
		return nil, err
	}

	// success!
	options := &Options{
		Input: input,
		Table: tennis.Table{
			Color:      tennis.StringToColor(cmd.String("color")),
			Output:     ctx.Output,
			RowNumbers: cmd.Bool("row-numbers"),
			Theme:      tennis.StringToTheme(cmd.String("theme")),
			Title:      cmd.String("title"),
		},
	}
	return options, nil
}

//
// helpers
//

func getInput(ctx *MainContext, cmd *cli.Command) (io.Reader, error) {
	// first argument, if any
	fileArg := cmd.Args().First()
	switch {
	// tennis a.csv b.csv
	case cmd.Args().Len() > 1:
		return nil, errors.New("too many arguments")

	// cat something.csv | tennis     OR   tennis
	// cat something.csv | tennis -   OR   tennis -
	case fileArg == "" || fileArg == "-":
		if isTty(ctx.Input) {
			return nil, errors.New("could not read stdin")
		}
		// stdin is file/pipe
		return ctx.Input, nil
	}

	// tennis something.csv
	return os.Open(fileArg) //nolint:wrapcheck
}

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
