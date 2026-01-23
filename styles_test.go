package tennis

import (
	"testing"

	"github.com/charmbracelet/colorprofile"
	"github.com/charmbracelet/lipgloss/v2"
	"github.com/stretchr/testify/assert"
)

func TestStyles(t *testing.T) {
	// ascii
	ascii := constructStyles(colorprofile.Ascii, ThemeDark)
	assert.Equal(t, lipgloss.NewStyle(), ascii.chrome)

	// REMIND: light
	// REMIND: dark
}
