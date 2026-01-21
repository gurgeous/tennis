package tennis

import (
	"slices"
	"sort"
	"strconv"
	"strings"

	"github.com/samber/lo"
)

const (
	fudge = 2
)

func (t *Table) constructLayout() []int {
	// How much space is available, and do we already fit?
	dataWidths := t.measureDataWidths()
	available := t.TermWidth - chromeWidth(dataWidths) - fudge
	if available >= tableWidth(dataWidths) {
		return slices.Clone(dataWidths)
	}

	// We don't fit, so we are going to shrink (truncate) some columns. Potentially all the way down
	// to a lower bound. But what is the lower bound? It's nice to have a generous value so that
	// narrow columns have a shot at avoiding truncation. That isn't always possible, though.
	lowerBound := lo.Clamp(available/len(dataWidths), 2, 10)

	// Calculate a "min" and a "max" data width for each column, then allocate available space
	// proportionally to each column. This is similar to the algorithm for HTML tables.
	dmin := lo.Map(dataWidths, func(x int, _ int) int { return min(x, lowerBound) })
	dmax := dataWidths

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
	diffs := mapIndex(dataWidths, func(ii int) int { return dmax[ii] - dmin[ii] })
	layout := mapIndex(dataWidths, func(ii int) int { return dmin[ii] + int(float64(diffs[ii])*ratio) })

	// because we always round down, there might be some extra space to distribute
	if extraSpace := available - tableWidth(layout); extraSpace > 0 {
		indexes := lo.Range(len(dataWidths))
		sort.SliceStable(indexes, func(a, b int) bool { return diffs[b] < diffs[a] })
		for i := 0; i < extraSpace && i < len(indexes); i++ {
			layout[indexes[i]]++
		}
	}

	return layout
}

// Measure the size of each column. Fails if the records are ragged
func (t *Table) measureDataWidths() []int {
	dataWidths := make([]int, len(t.headers))
	for ii := range dataWidths {
		dataWidths[ii] = minFieldWidth
	}
	for _, record := range t.records {
		for ii, data := range record {
			data = strings.TrimSpace(data)
			record[ii] = data
			dataWidths[ii] = max(dataWidths[ii], len(data))
		}
	}
	if t.RowNumbers {
		n := len(t.records) - 1
		ndigits := len(strconv.Itoa(n))
		unshift(&dataWidths, max(ndigits, minFieldWidth))
	}
	return dataWidths
}

//
// helpers
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
