package main

import (
	"fmt"
	"os"
	"time"

	"github.com/charmbracelet/lipgloss"
	"github.com/samber/lo"
	"golang.org/x/term"
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

//
// banner
//

func banner(msg string, bg lipgloss.Color) {
	msg = fmt.Sprintf("[%s] %s", time.Now().Format("15:04:05"), msg)
	fmt.Fprintln(os.Stdout, BASE.Background(bg).Render(msg))
}

func Banner(msg string) {
	banner(msg, GREEN)
}

func Warning(msg string) {
	banner(msg, YELLOW)
}

func Fatal(msg string, err error) {
	if err != nil {
		msg += ": " + err.Error()
	}
	banner(msg, RED)
	os.Exit(1)
}

//
// generics
//

func MapIndex[T, R any](collection []T, iteratee func(index int) R) []R {
	return lo.Map(collection, func(_ T, index int) R { return iteratee(index) })
}

//
// misc
//

func TermWidth() int {
	termWidth, _, err := term.GetSize(int(os.Stdout.Fd()))
	if err != nil {
		termWidth = 80
	}
	return termWidth
}

// type Number interface {
// 	int | int64 | float32 | float64
// }

// func Clamp[T Number](x, min, max T) T {
// 	if x < min {
// 		return min
// 	}
// 	if x > max {
// 		return max
// 	}
// 	return x
// }

// func CopySlice[T Number](slice []T) []T {
// 	result := make([]T, len(slice))
// 	copy(result, slice)
// 	return result
// }

// func Sum[T Number](slice []T) T {
// 	var sum T
// 	for _, v := range slice {
// 		sum += v
// 	}
// 	return sum
// }
