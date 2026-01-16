package main

import (
	"slices"
	"sort"

	"github.com/samber/lo"
)

// |•xxxx•|•xxxx•|•xxxx•|•xxxx•|•xxxx•|•xxxx•|•xxxx•|•xxxx•|
// ↑↑    ↑                                                 ↑
// 12    3    <-   three chrome chars per column           │
//                                                         │
//                                           extra chrome char at the end

const FUDGE = 2

func AutoLayout(widths []int, termWidth int) []int {
	chromeWidth := len(widths)*3 + 1
	tableWidth := lo.Sum(widths)

	// How much space is available, and do we already fit?
	available := termWidth - chromeWidth - FUDGE
	if available >= tableWidth {
		return slices.Clone(widths)
	}

	// We don't fit, so we are going to shrink (truncate) some columns. Potentially all the way down
	// to a lower bound. But what is the lower bound? It's nice to have a generous value so that
	// narrow columns have a shot at avoiding truncation. That isn't always possible, though.
	lowerBound := lo.Clamp(available/len(widths), 2, 10)

	// Calculate a "min" and a "max" data width for each column, then allocate available space
	// proportionally to each column. This is similar to the algorithm for HTML tables.
	dmin := lo.Map(widths, func(x int, _ int) int { return min(x, lowerBound) })
	dmax := widths

	// W = difference between the available space and the minimum table width
	// D = difference between maximum and minimum table width
	// ratio = W / D
	minSum, maxSum := lo.Sum(dmin), lo.Sum(dmax)
	ratio := float64(available-minSum) / float64(maxSum-minSum)
	if ratio < 0 {
		// sadly, even dmin doesn't fit
		return dmin
	}

	// col.width = col.min + ((col.max - col.min) * ratio)
	diffs := MapIndex(widths, func(ii int) int { return dmax[ii] - dmin[ii] })
	layout := MapIndex(widths, func(ii int) int { return dmin[ii] + int(float64(diffs[ii])*ratio) })
	tableWidth = lo.Sum(layout)

	// because we always round down, there might be some extra space to distribute
	if extraSpace := available - tableWidth; extraSpace > 0 {
		indexes := lo.Range(len(widths))
		sort.SliceStable(indexes, func(a, b int) bool { return diffs[b] < diffs[a] })
		for i := 0; i < extraSpace && i < len(indexes); i++ {
			layout[indexes[i]]++
		}
	}

	return layout
}
