package tennis

import (
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
)

func AssertEqualTrim(t *testing.T, expected, actual string) {
	assert.Equal(t, strings.TrimSpace(expected), strings.TrimSpace(actual))
}
