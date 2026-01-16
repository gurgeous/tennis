package main

import (
	"github.com/charmbracelet/lipgloss"
	"github.com/samber/lo"
)

var (
	// styles
	Chrome  = lipgloss.NewStyle().Foreground(chrome)
	Field   = lipgloss.NewStyle().Foreground(field)
	Headers = lo.Map(headers, func(color lipgloss.AdaptiveColor, _ int) lipgloss.Style {
		return lipgloss.NewStyle().Foreground(color).Bold(true)
	})

	// colors
	chrome  = lipgloss.AdaptiveColor{Light: Tailwind.Gray.c500, Dark: Tailwind.Gray.c500}
	field   = lipgloss.AdaptiveColor{Light: Tailwind.Gray.c800, Dark: Tailwind.Gray.c200}
	headers = []lipgloss.AdaptiveColor{
		{Light: "#ee4066", Dark: "#ff6188"}, // red/pink
		{Light: "#da7645", Dark: "#fc9867"}, // orange
		{Light: "#ddb644", Dark: "#ffd866"}, // yellow
		{Light: "#87ba54", Dark: "#a9dc76"}, // green
		{Light: "#56bac6", Dark: "#78dce8"}, // cyan
		{Light: "#897bd0", Dark: "#ab9df2"}, // purple
	}
)
