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

// see .goreleaser.yaml
var Version = ""

// HideHelp?
// EnableShellCompletion
// InvalidFlagAccessHandler
// Hidden?
// Reader/Writer/ErrWriter?
// AllowExtFlags
// Arguments
// isInError

type Options struct {
	Table tennis.Table // a configured table
	Input io.Reader    // where to read
}

func options(ctx *MainContext) *Options {
	const banner = "tennis: try 'tennis --help' for more information"

	//
	// handle the naked case early for simplicity
	//

	if len(ctx.Args) == 0 && isTty(ctx.Input) {
		fmt.Fprintln(ctx.Output, banner)
		ctx.Exit(0)
		return nil // only reached during tests
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
		Name:            "tennis",
		Usage:           "Stylish CSV tables in your terminal.",
		ArgsUsage:       "[file.csv]",
		Version:         Version,
		Reader:          ctx.Input,
		Writer:          ctx.Output,
		ErrWriter:       ctx.Output,
		HideHelpCommand: true,
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

		// overridden (as nop) to avoid default behavior that we don't care for
		Action:         func(_ context.Context, _ *cli.Command) error { return nil },
		ExitErrHandler: func(_ context.Context, _ *cli.Command, _ error) {},
		OnUsageError:   func(_ context.Context, _ *cli.Command, err error, _ bool) error { return err },
	}

	//
	// parse
	//

	var input io.Reader
	err := cmd.Run(context.Background(), append([]string{"tennis"}, ctx.Args...))

	//
	// if err is nil, handle --version and/or try to open the file
	//

	if err == nil {
		if cmd.Bool("version") {
			ctx.Exit(0)
			return nil // only reached during tests
		}
		input, err = getInput(ctx, cmd)
	}

	//
	// error handling
	//

	if err != nil {
		fmt.Fprintf(ctx.Output, "tennis: %s\n", err.Error())
		fmt.Fprintln(ctx.Output, banner)
		ctx.Exit(1)
		return nil // only reached during tests
	}

	//
	// success!
	//

	return &Options{
		Input: input,
		Table: tennis.Table{
			Color:      tennis.StringToColor(cmd.String("color")),
			Output:     ctx.Output,
			RowNumbers: cmd.Bool("row-numbers"),
			Theme:      tennis.StringToTheme(cmd.String("theme")),
			Title:      cmd.String("title"),
		},
	}
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
