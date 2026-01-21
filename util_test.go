package tennis

import (
	"reflect"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestMapIndex(t *testing.T) {
	array := mapIndex([]int{123, 456}, func(ii int) int { return ii * 2 })
	assert.Equal(t, array, []int{0, 2})
}

func TestPush(t *testing.T) {
	array := []int{123}
	push(&array, 456)
	assert.True(t, reflect.DeepEqual(array, []int{123, 456}))
}

func TestPop(t *testing.T) {
	array := []int{123}
	value, ok := pop(&array)
	assert.Equal(t, 123, value)
	assert.True(t, ok)
	assert.Equal(t, array, []int{})

	_, ok = pop(&array)
	assert.False(t, ok)
	assert.Equal(t, array, []int{})
}

func TestShift(t *testing.T) {
	array := []int{123}
	value, ok := shift(&array)
	assert.Equal(t, 123, value)
	assert.True(t, ok)
	assert.Equal(t, array, []int{})

	_, ok = shift(&array)
	assert.False(t, ok)
	assert.Equal(t, array, []int{})
}

func TestUnshift(t *testing.T) {
	array := []int{456}
	unshift(&array, 123)
	assert.True(t, reflect.DeepEqual(array, []int{123, 456}))
}
