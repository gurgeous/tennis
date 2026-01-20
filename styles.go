package tennis

import "github.com/charmbracelet/lipgloss/v2"

//
// 1. rename "w" => Forward (to match charm)
// 2. when we start rendering, create a colorprofile writer for downsampling
// 3. at runtime, use LightDark to create styles
//

type styles struct {
	chrome lipgloss.Style
	field  lipgloss.Style
	// headers []lipgloss.Style
}

func (t *Table) createStyles() *styles {
	lightDark := lipgloss.LightDark(t.Theme != ThemeLight)

	chrome := lipgloss.Color(Tailwind.Gray.c500)
	field := lightDark(
		lipgloss.Color(Tailwind.Gray.c800),
		lipgloss.Color(Tailwind.Gray.c200),
	)

	return &styles{
		chrome: lipgloss.NewStyle().Foreground(chrome),
		field:  lipgloss.NewStyle().Foreground(field),
	}
}

// https://github.com/charmbracelet/lipgloss/discussions/506
// func NewWriter(w io.Writer, environ []string) *Writer {
// 	return &Writer{
// 		Forward: w,
// 		Profile: Detect(w, environ),
// 	}
// }
// https://github.com/charmbracelet/colorprofile/blob/main/writer.go

// they have a new down-sampling writer
//
// s := someStyle.Render("Hello!")
// Downsample and print to stdout.
// lipgloss.Println(s)
// Render to a variable.
// downsampled := lipgloss.Sprint(s)
// lipgloss.Fprint(os.Stderr, s)

// standalone color stuff
//
// Detect the background color. Notice we're writing to stderr.
// hasDarkBG, err := lipgloss.HasDarkBackground(os.Stdin, os.Stderr)
// if err != nil {
//     log.Fatal("Oof:", err)
// }
// // Create a helper for choosing the appropriate color.
// lightDark := lipgloss.LightDark(hasDarkBG)
// // Declare some colors.
// thisColor := lightDark("#C5ADF9", "#864EFF")
// thatColor := lightDark("#37CD96", "#22C78A")
// // Render some styles.
// a := lipgloss.NewStyle().Foreground(thisColor).Render("this")
// b := lipgloss.NewStyle().Foreground(thatColor).Render("that")
// // Print to stderr.
// lipgloss.Fprintf(os.Stderr, "my fave colors are %s and %s...for now.", a, b)

var (

// // styles
// Chrome  = lipgloss.NewStyle().Foreground(chrome)
// Field   = lipgloss.NewStyle().Foreground(field)
// Headers = lo.Map(headers, func(color lipgloss.AdaptiveColor, _ int) lipgloss.Style {
// 	return lipgloss.NewStyle().Foreground(color).Bold(true)
// })

// // colors
// chrome  = lipgloss.Color(Tailwind.Gray.c500)
// field   = lipgloss.AdaptiveColor{Light: Tailwind.Gray.c800, Dark: Tailwind.Gray.c200}
//
//	headers = []lipgloss.AdaptiveColor{
//		{Light: "#ee4066", Dark: "#ff6188"}, // red/pink
//		{Light: "#da7645", Dark: "#fc9867"}, // orange
//		{Light: "#ddb644", Dark: "#ffd866"}, // yellow
//		{Light: "#87ba54", Dark: "#a9dc76"}, // green
//		{Light: "#56bac6", Dark: "#78dce8"}, // cyan
//		{Light: "#897bd0", Dark: "#ab9df2"}, // purple
//	}
)
