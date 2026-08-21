package main

import (
	"fmt"
	"slices"
)

type Buffer struct {
	lines []string
}

// Normalizes 0-based indexes (same in Neovim)
// -1, one past last index, for appending (slices allow this)
// -2, last line...
func normalizeIndex(index, length int) int {
	if index < 0 {
		index = length + index + 1
	}

	return max(0, min(index, length))
}

// GetLines returns a slice of lines between start and end (exclusive)
func (b *Buffer) GetLines(start, end int) ([]string, error) {
	length := len(b.lines)
	start = normalizeIndex(start, length)
	end = normalizeIndex(end, length)

	if start > end {
		start = end
	}

	return slices.Clone(b.lines[start:end]), nil
}

// SetLines replaces a range of lines with the replacement slice
func (b *Buffer) SetLines(start, end int, replacement []string) error {
	length := len(b.lines)
	start = normalizeIndex(start, length)
	end = normalizeIndex(end, length)

	if start > end {
		start = end
	}

	b.lines = slices.Replace(b.lines, start, end, replacement...)
	return nil
}

func main() {
	b := &Buffer{
		lines: []string{"Mustan", "Kissan", "Paksut", "Posket"},
	}

	lines, _ := b.GetLines(0, -1)
	for i, l := range lines {
		fmt.Printf("%d: %s\n", i, l)
	}

	b.SetLines(0, 1, []string{"Oranssin"})

	lines, _ = b.GetLines(0, -1)
	for i, l := range lines {
		fmt.Printf("%d: %s\n", i, l)
	}

}
