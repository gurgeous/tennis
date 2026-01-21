package tennis

import (
	"image/color"

	"github.com/charmbracelet/lipgloss/v2"
	"github.com/samber/lo"
)

//
// 1. rename "w" => Forward (to match charm)
// 2. when we start rendering, create a colorprofile writer for downsampling
// 3. at runtime, use LightDark to create styles
//

type styles struct {
	chrome  lipgloss.Style
	field   lipgloss.Style
	headers []lipgloss.Style
}

func (t *Table) createStyles() *styles {
	lightDark := lipgloss.LightDark(t.ThemeChoice != ThemeChoiceLight)

	chrome := lipgloss.Color(Tailwind.Gray.c500)
	field := lightDark(
		lipgloss.Color(Tailwind.Gray.c800),
		lipgloss.Color(Tailwind.Gray.c200),
	)
	headers := []color.Color{
		lightDark(lipgloss.Color("#ee4066"), lipgloss.Color("#ff6188")), // red/pink
		lightDark(lipgloss.Color("#da7645"), lipgloss.Color("#fc9867")), // orange
		lightDark(lipgloss.Color("#ddb644"), lipgloss.Color("#ffd866")), // yellow
		lightDark(lipgloss.Color("#87ba54"), lipgloss.Color("#a9dc76")), // green
		lightDark(lipgloss.Color("#56bac6"), lipgloss.Color("#78dce8")), // cyan
		lightDark(lipgloss.Color("#897bd0"), lipgloss.Color("#ab9df2")), // purple
	}

	return &styles{
		chrome: lipgloss.NewStyle().Foreground(chrome),
		field:  lipgloss.NewStyle().Foreground(field),
		headers: lo.Map(headers, func(color color.Color, _ int) lipgloss.Style {
			return lipgloss.NewStyle().Foreground(color).Bold(true)
		}),
	}
}
