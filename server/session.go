package main

import (
	"io/fs"
	"strings"
	"sync"
)

type Session struct {
	buffers sync.Map
	fsys    fs.FS
	rootDir string
	ignored []string
}

// FindBufferByPath returns an existing buffer for the path, or creates a new one
func (s *Session) FindBufferByPath(path string) *Buffer {
	if v, ok := s.buffers.Load(path); ok {
		return v.(*Buffer)
	}

	b := NewBuffer(path)
	actual, loaded := s.buffers.LoadOrStore(path, b)
	if loaded {
		// Another conn got it before
		return actual.(*Buffer)
	}

	raw, err := fs.ReadFile(s.fsys, path)
	if err == nil {
		content := strings.ReplaceAll(string(raw), "\r\n", "\n")
		lines := strings.Split(content, "\n")
		b.SetLines(0, len(b.lines), lines)
	}

	return b
}
