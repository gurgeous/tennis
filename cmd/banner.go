//nolint:unused
package main

import (
	"fmt"
	"image/color"
	"os"
	"time"

	"github.com/charmbracelet/lipgloss/v2"
)

var (
	BASE = lipgloss.NewStyle().
		Foreground(lipgloss.Color("#fff")).
		Bold(true).
		Width(85)
	GREEN  = lipgloss.Color("#728a07")
	YELLOW = lipgloss.Color("#a57705")
	RED    = lipgloss.Color("#d11b23")
)

func banner0(msg string, bg color.Color) {
	msg = fmt.Sprintf("[%s] %s", time.Now().Format("15:04:05"), msg)
	fmt.Fprintln(os.Stdout, BASE.Background(bg).Render(msg))
}

func banner(msg string) {
	banner0(msg, GREEN)
}

func warning(msg string) {
	banner0(msg, YELLOW)
}

func fatal(msg string, err error) {
	if err != nil {
		msg += ": " + err.Error()
	}
	banner0(msg, RED)
	os.Exit(1)
}
