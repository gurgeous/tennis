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

// func Unshift[T any](array []T, x T) []T {
// 	return append([]T{x}, array...)
// }

// func push[T any](array *[]T, el T) {
// 	*array = append(*array, el)
// }

// func pop[T any](array *[]T) (T, bool) {
// 	if len(*array) == 0 {
// 		var out T
// 		return out, false
// 	}
// 	count := len(*array)
// 	el := (*array)[count-1]
// 	*array = (*array)[:count-1]
// 	return el, true
// }

// func shift[T any](array *[]T) (T, bool) {
// 	if len(*array) == 0 {
// 		var out T
// 		return out, false
// 	}
// 	el := (*array)[0]
// 	*array = (*array)[1:]
// 	return el, true
// }

func unshift[T any](array *[]T, el T) {
	*array = append([]T{el}, *array...)
}

//
// table layout
//

// |•xxxx•|•xxxx•|•xxxx•|•xxxx•|•xxxx•|•xxxx•|•xxxx•|•xxxx•|
// ↑↑    ↑                                                 ↑
// 12    3    <-   three chrome chars per column           │
//                                                         │
//                                           extra chrome char at the end

func chromeWidth(layout []int) int {
	return len(layout)*3 + 1
}

// width of all data in one row according to this layout
func dataWidth(layout []int) int {
	return lo.Sum(layout)
}

// total width of table, according to this layout
func tableWidth(layout []int) int {
	return chromeWidth(layout) + dataWidth(layout)
}
