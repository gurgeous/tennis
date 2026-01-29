package tennis

import (
	"strings"

	"github.com/charmbracelet/x/ansi"
	"github.com/samber/lo"
)

// map range to something else
func mapIndex[T, R any](collection []T, iteratee func(index int) R) []R {
	return lo.Map(collection, func(_ T, index int) R { return iteratee(index) })
}

//
// arrays
//

func push[T any](array *[]T, el T) {
	*array = append(*array, el)
}

func pop[T any](array *[]T) (T, bool) {
	if len(*array) == 0 {
		var out T
		return out, false
	}
	count := len(*array)
	el := (*array)[count-1]
	*array = (*array)[:count-1]
	return el, true
}

func shift[T any](array *[]T) (T, bool) {
	if len(*array) == 0 {
		var out T
		return out, false
	}
	el := (*array)[0]
	*array = (*array)[1:]
	return el, true
}

func unshift[T any](array *[]T, el T) {
	*array = append([]T{el}, *array...)
}

//
// some ansi helpers
//

const resetStyle = ansi.ResetStyle

// style str using codes (if any)
func style(codes string, str string) string {
	if len(codes) == 0 {
		return str
	}
	return codes + str + resetStyle
}

// like style(), but into a buf
func styleInto(buf *strings.Builder, codes string, str string) {
	if len(codes) == 0 {
		buf.WriteString(str)
		return
	}

	buf.WriteString(codes)
	buf.WriteString(str)
	buf.WriteString(resetStyle)
}
