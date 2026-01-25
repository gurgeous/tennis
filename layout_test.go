package tennis

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestLayout(t *testing.T) {
	input := []int{32, 20, 10}
	layout1 := constructLayout(input, 100)
	assert.Equal(t, input, layout1)
	layout2 := constructLayout(input, 50)
	assert.Equal(t, []int{15, 12, 10}, layout2)
}
