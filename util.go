package tennis

import (
	"github.com/samber/lo"
)

func MapIndex[T, R any](collection []T, iteratee func(index int) R) []R {
	return lo.Map(collection, func(_ T, index int) R { return iteratee(index) })
}
