package main

import (
	"fmt"
	"io/fs"
	"os"
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
	relPath := b.path
	content := strings.Join(b.lines, "\n")
	b.mu.RUnlock()

	// Rotanloukku
	if !fs.ValidPath(relPath) {
		return fmt.Errorf("illegal path: %q", relPath)
	}

	root, err := os.OpenRoot(rootDir)
	if err != nil {
		return fmt.Errorf("failed to open root dir: %w", err)
	}
	defer root.Close()

	mode := os.FileMode(0644)
	if info, err := root.Stat(relPath); err == nil {
		mode = info.Mode()
	}

	return root.WriteFile(relPath, []byte(content), mode)
}

// Lines returns a slice of lines between start and end (exclusive)
func (b *Buffer) Lines(start, end int) ([]string, error) {
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
		index = length + index + 1
	}
	return max(0, min(index, length))
}
