package tennis

import (
	"github.com/charmbracelet/colorprofile"
	"github.com/charmbracelet/lipgloss/v2"
	"github.com/samber/lo"
)

type styles struct {
	chrome  lipgloss.Style
	field   lipgloss.Style
	title   lipgloss.Style
	headers []lipgloss.Style
}

func constructStyles(profile colorprofile.Profile, theme Theme) *styles {
	// ascii? nop
	if profile <= colorprofile.Ascii {
		nop := lipgloss.NewStyle()
		return &styles{
			headers: []lipgloss.Style{nop},
		}
	}

	//
	// dark/light colors
	//

	var chrome, field, title string
	var headers []string
	if theme == ThemeDark {
		chrome, field, title = Tailwind.Gray.c500, Tailwind.Gray.c200, Tailwind.Blue.c400
		headers = []string{"#ff6188", "#fc9867", "#ffd866", "#a9dc76", "#78dce8", "#ab9df2"}
	} else {
		chrome, field, title = Tailwind.Gray.c500, Tailwind.Gray.c800, Tailwind.Blue.c600
		headers = []string{"#ee4066", "#da7645", "#ddb644", "#87ba54", "#56bac6", "#897bd0"}
	}

	//
	// now styles
	//

	// create/downsample color to match profile
	downsample := func(hex string) lipgloss.Style {
		fg := profile.Convert(lipgloss.Color(hex))
		return lipgloss.NewStyle().Foreground(fg)
	}

	return &styles{
		chrome: downsample(chrome),
		field:  downsample(field),
		title:  downsample(title).Bold(true),
		headers: lo.Map(headers, func(hex string, _ int) lipgloss.Style {
			return downsample(hex).Bold(true)
		}),
	}
}
