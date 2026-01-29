package main

import (
	"errors"
	"fmt"
	"io"
	"os"
	"slices"
	"strconv"

	"github.com/charmbracelet/x/term"
	"github.com/gurgeous/tennis"
	"github.com/spf13/pflag"
)

//
// options is responsible for parsing cli args
//

type Options struct {
	Table  tennis.Table // a configured table
	Input  io.Reader    // where to read
	Closer io.Closer    // closer, if any
}

const banner = "tennis: try 'tennis --help' for more information"

//
// mostly a wrapper around parseOptions, for handling errors and calling ctx.Exit
//

func NewOptions(ctx *MainContext) *Options {
	opts, err := parseOptions(ctx)
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

func parseOptions(ctx *MainContext) (*Options, error) {
	// handle the naked case early for simplicity
	input := ctx.Input
	if len(ctx.Args) == 0 && isTty(input) {
		fmt.Fprintln(ctx.Output, banner)
		return nil, nil
	}

	//
	// setup flags
	//

	fs := pflag.NewFlagSet("tennis", pflag.ContinueOnError)
	fs.SetOutput(ctx.Output)
	fs.SortFlags = false
	fs.Usage = func() {
		fmt.Fprintln(ctx.Output, "Usage: tennis [options] [file.csv]")
		fs.PrintDefaults()
	}
	colorFlag := fs.String("color", "auto", "Turn color off and on with auto|never|always")
	themeFlag := fs.String("theme", "auto", "Select color theme auto|dark|light")
	rowNumbers := fs.BoolP("row-numbers", "n", false, "Turn on row numbers")
	titleFlag := fs.StringP("title", "t", "", "Add a pretty title at the top")
	widthFlag := fs.IntP("width", "w", 0, "Set max table width in columns (0 = auto)")
	versionFlag := fs.Bool("version", false, "Print the version number")

	//
	// parse args, handle --version, etc.
	//

	if err := fs.Parse(ctx.Args); err != nil {
		// handle --help
		if errors.Is(err, pflag.ErrHelp) {
			return nil, nil
		}
		return nil, err //nolint:wrapcheck
	}

	// handle --version
	if *versionFlag {
		version := tennis.Version
		if version == "" {
			version = "unknown (built from source)"
		}
		fmt.Fprintln(ctx.Output, version)
		return nil, nil
	}

	// check --color and --theme
	if err := isOneOf(*colorFlag, "auto", "never", "always"); err != nil {
		return nil, fmt.Errorf("invalid --color: %w", err)
	}
	if err := isOneOf(*themeFlag, "auto", "dark", "light"); err != nil {
		return nil, fmt.Errorf("invalid --theme: %w", err)
	}
	if *widthFlag < 0 {
		return nil, errors.New("invalid --width: must be >= 0")
	}

	//
	// input handling
	//

	input, closer, err := getInput(input, fs.Args())
	if err != nil {
		return nil, err
	}

	//
	// success!
	//

	return &Options{
		Input:  input,
		Closer: closer,
		Table: tennis.Table{
			Color:      tennis.StringToColor(*colorFlag),
			Output:     ctx.Output,
			RowNumbers: *rowNumbers,
			TermWidth:  *widthFlag,
			Theme:      tennis.StringToTheme(*themeFlag),
			Title:      *titleFlag,
		},
	}, nil
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

//
// what is our input?
//

func getInput(input io.Reader, args []string) (io.Reader, io.Closer, error) {
	fileArg := ""
	if len(args) > 0 {
		fileArg = args[0]
	}
	switch {
	// tennis a.csv b.csv
	case len(args) > 1:
		return nil, nil, errors.New("too many arguments")

	// cat something.csv | tennis     OR   tennis
	// cat something.csv | tennis -   OR   tennis -
	case fileArg == "" || fileArg == "-":
		if isTty(input) {
			return nil, nil, errors.New("could not read stdin")
		}
		// stdin is file/pipe
		return input, nil, nil
	}

	// tennis something.csv
	file, err := os.Open(fileArg)
	if err != nil {
		return nil, nil, err //nolint:wrapcheck
	}
	return file, file, nil
}
