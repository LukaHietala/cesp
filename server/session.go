package main

import (
	"io/fs"
	"log"
	"strings"
	"sync"
)

type Session struct {
	buffers     sync.Map
	fsys        fs.FS
	rootDir     string
	ignoredDirs map[string]bool
}

// GetBuffer returns an existing buffer for the path, or creates a new one
func (s *Session) GetBuffer(path string) *Buffer {
	if v, ok := s.buffers.Load(path); ok {
		return v.(*Buffer)
	}

	b := NewBuffer(path)
	content, err := fs.ReadFile(s.fsys, path)
	if err == nil {
		lines := strings.Split(string(content), "\n")
		b.SetLines(0, -1, lines)
	}

	actual, _ := s.buffers.LoadOrStore(path, b)
	return actual.(*Buffer)
}

// Saves all buffers
func (s *Session) FlushAll() {
	s.buffers.Range(func(k, v any) bool {
		b := v.(*Buffer)
		err := b.Save(s.rootDir)
		if err != nil {
			log.Println(err)
		}
		return true
	})
}
