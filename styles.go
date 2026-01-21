package tennis

import (
	"image/color"

	"github.com/charmbracelet/lipgloss/v2"
	"github.com/samber/lo"
)

type styles struct {
	chrome  lipgloss.Style
	field   lipgloss.Style
	headers []lipgloss.Style
}

func (t *Table) constructStyles() *styles {
	lightDark := lipgloss.LightDark(t.Theme != ThemeLight)
	chrome := t.constructColor(Tailwind.Gray.c500)
	field := lightDark(
		t.constructColor(Tailwind.Gray.c800),
		t.constructColor(Tailwind.Gray.c200),
	)
	headers := []color.Color{
		lightDark(t.constructColor("#ee4066"), t.constructColor("#ff6188")), // red/pink
		lightDark(t.constructColor("#da7645"), t.constructColor("#fc9867")), // orange
		lightDark(t.constructColor("#ddb644"), t.constructColor("#ffd866")), // yellow
		lightDark(t.constructColor("#87ba54"), t.constructColor("#a9dc76")), // green
		lightDark(t.constructColor("#56bac6"), t.constructColor("#78dce8")), // cyan
		lightDark(t.constructColor("#897bd0"), t.constructColor("#ab9df2")), // purple
	}

	{
		chrome := lipgloss.NewStyle().Foreground(chrome)
		field := lipgloss.NewStyle().Foreground(field)
		headers := lo.Map(headers, func(color color.Color, _ int) lipgloss.Style {
			return lipgloss.NewStyle().Foreground(color).Bold(true)
		})

		// styles
		return &styles{chrome, field, headers}
	}
}

func (t *Table) constructColor(s string) color.Color {
	// create/downsample color to match profile
	return t.profile.Convert(lipgloss.Color(s))
}
