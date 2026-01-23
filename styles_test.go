package tennis

import (
	"testing"

	"github.com/charmbracelet/colorprofile"
	"github.com/stretchr/testify/assert"
)

func TestStyles(t *testing.T) {
	// ascii
	ascii1 := constructStyles(colorprofile.Ascii, ThemeDark)
	ascii2 := constructStyles(colorprofile.Ascii, ThemeLight)
	assert.Equal(t, "", ascii1.title)
	assert.Equal(t, "", ascii2.title)
	// dark bold/blue-400
	dark := constructStyles(colorprofile.TrueColor, ThemeDark)
	assert.Equal(t, "\x1b[1;38;2;96;165;250m\x1b[m", dark.title)
	// light bold/blue-600
	light := constructStyles(colorprofile.TrueColor, ThemeLight)
	assert.Equal(t, "\x1b[1;38;2;37;99;235m\x1b[m", light.title)
}

// REMIND: downsample
