package main

import (
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"sync"
)

type Buffer struct {
	mu    sync.RWMutex
	path  string
	lines []string
}

func NewBuffer(path string) *Buffer {
	return &Buffer{
		path:  path,
		lines: []string{""},
	}
}

// Save saves a buffer
func (b *Buffer) Save(rootDir string) error {
	b.mu.RLock()
	// Rotanloukku
	slashPath := filepath.ToSlash(b.path)
	if !fs.ValidPath(slashPath) {
		b.mu.RUnlock()
		return fmt.Errorf("illegal path %s", b.path)
	}
	content := strings.Join(b.lines, "\n")
	b.mu.RUnlock()

	fullPath := filepath.Join(rootDir, b.path)

	return os.WriteFile(fullPath, []byte(content), 0644)
}

// GetLines returns a slice of lines between start and end (exclusive)
func (b *Buffer) GetLines(start, end int) ([]string, error) {
	b.mu.RLock()
	defer b.mu.RUnlock()

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
	b.mu.Lock()
	defer b.mu.Unlock()

	length := len(b.lines)
	start = normalizeIndex(start, length)
	end = normalizeIndex(end, length)

	if start > end {
		start = end
	}

	b.lines = slices.Replace(b.lines, start, end, replacement...)
	return nil
}

func normalizeIndex(index, length int) int {
	if index < 0 {
		index = length + index
	}
	return max(0, min(index, length))
}
