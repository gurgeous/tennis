//nolint:unused
package tennis

import (
	"github.com/samber/lo"
)

//
// collections
//

func mapIndex[T, R any](collection []T, iteratee func(index int) R) []R {
	return lo.Map(collection, func(_ T, index int) R { return iteratee(index) })
}

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
