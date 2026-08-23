package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"io/fs"
	"log"
	"net"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"sync"
	"time"
)

// TODO:
// Save all bufs when os signal
// Ignored files and dirs
// SSH Tunnel (autossh like)
// JSON v2

type Buffer struct {
	mu    sync.RWMutex
	path  string
	lines []string
}

type Session struct {
	mu      sync.RWMutex
	buffers map[string]*Buffer
	fsys    fs.FS
	rootDir string
}

func main() {
	// TCP connection hub
	hub := NewHub()
	go hub.Run()

	// Shared dir
	rootDir := "."
	fsys := os.DirFS(rootDir)

	// Make sure fsys is valid
	if _, err := GetFiles(fsys); err != nil {
		log.Fatal(err)
	}

	session := &Session{
		buffers: make(map[string]*Buffer),
		fsys:    fsys,
		rootDir: rootDir,
	}

	// TODO: Port, debug, ignored flags, shared dir
	listener, err := net.Listen("tcp", ":8080")
	if err != nil {
		log.Fatal(err)
	}
	defer listener.Close()

	log.Println("Listening on :8080")

	for {
		conn, err := listener.Accept()
		if err != nil {
			log.Println(err)
			continue
		}

		go handleConn(conn, session, hub)
	}
}

func handleConn(conn net.Conn, session *Session, hub *Hub) {
	client := &Client{
		conn: conn,
		send: make(chan string, 100),
	}

	hub.register <- client

	defer func() {
		hub.unregister <- client
		conn.Close()
		log.Println("Connection closed:", conn.RemoteAddr())
	}()

	// TODO: Heartbeat to conns
	conn.SetReadDeadline(time.Now().Add(5 * time.Minute))
	log.Println("New connection: ", conn.RemoteAddr())

	// Write pump
	go func() {
		for msg := range client.send {
			fmt.Fprintln(conn, msg)
		}
	}()

	// Max 5MB buffer
	const maxCap = 1024 * 1024 * 5
	scanner := bufio.NewScanner(conn)
	buf := make([]byte, maxCap)
	scanner.Buffer(buf, maxCap)

	// Read pump
	for {
		conn.SetReadDeadline(time.Now().Add(5 * time.Minute))

		if !scanner.Scan() {
			break
		}

		text := strings.TrimSpace(scanner.Text())
		if text == "" {
			continue
		}

		log.Println("Received: ", text)

		var msg EventMessage
		if err := json.Unmarshal([]byte(text), &msg); err != nil {
			log.Println("Invalid JSON payload:", err)
			continue
		}

		switch msg.Event {
		case "request_files":
			files, err := GetFiles(session.fsys)
			if err != nil {
				log.Println("Error reading files:", err)
				continue
			}

			res := ResponseFiles{
				Event: "response_files",
				Files: files,
			}
			resBytes, _ := json.Marshal(res)
			client.send <- string(resBytes)

		case "request_file":
			b := session.GetBuffer(msg.Path)
			lines, _ := b.GetLines(0, -1)
			content := strings.Join(lines, "\n")

			res := ResponseFile{
				Event:   "response_file",
				Path:    msg.Path,
				Content: content,
			}
			resBytes, _ := json.Marshal(res)
			client.send <- string(resBytes)

		case "update_content":
			b := session.GetBuffer(msg.Path)

			b.SetLines(
				msg.Changes.First,
				msg.Changes.OldLast,
				msg.Changes.Lines,
			)

			hub.broadcast <- Message{
				sender: conn,
				event:  text,
			}

		case "cursor_move":
			hub.broadcast <- Message{
				sender: conn,
				event:  text,
			}

		case "remote_write":
			b := session.GetBuffer(msg.Path)
			if err := b.Save(session.rootDir); err != nil {
				log.Printf("Error saving %s: %v\n", msg.Path, err)
			} else {
				log.Printf("Saved %s\n", msg.Path)
			}

		default:
			log.Println("Unknown event", msg.Event)
		}
	}

	if err := scanner.Err(); err != nil {
		log.Println(err)
	}
}

// GetFiles returns all paths in DirFS
// TODO: filter
func GetFiles(fsys fs.FS) ([]string, error) {
	paths := []string{}

	err := fs.WalkDir(fsys, ".", func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}

		if d.IsDir() {
			return nil
		}

		paths = append(paths, path)
		return nil
	})

	return paths, err
}

// GetBuffer returns an existing buffer for the path, or creates a new one
func (s *Session) GetBuffer(path string) *Buffer {
	// Try to get existing
	s.mu.RLock()
	b, exists := s.buffers[path]
	s.mu.RUnlock()

	if exists {
		return b
	}

	// Create new and populate it with file content (if any)
	s.mu.Lock()
	defer s.mu.Unlock()

	// Check again to prevent duplicates
	// This is a flaw of this double lock, but it's better than constant delays
	if b, exists := s.buffers[path]; exists {
		return b
	}

	b = NewBuffer(path)

	content, err := fs.ReadFile(s.fsys, path)
	if err == nil {
		lines := strings.Split(string(content), "\n")
		b.SetLines(0, -1, lines)
	}

	s.buffers[path] = b
	return b
}

func NewBuffer(path string) *Buffer {
	return &Buffer{
		path: path,
		// Buffers should never be empty
		lines: []string{""},
	}
}

// Save saves buffer to path relative to root
// dirFs is readonly so root path is used directly
func (b *Buffer) Save(rootDir string) error {
	b.mu.RLock()
	defer b.mu.RUnlock()

	if !fs.ValidPath(b.path) {
		return fmt.Errorf("invalid path: %s", b.path)
	}

	fullPath := filepath.Join(rootDir, b.path)

	content := strings.Join(b.lines, "\n")
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

// Normalizes 0-based indexes (same in Neovim)
// -1, one past last index, for appending (slices allow this)
// -2, last line...
func normalizeIndex(index, length int) int {
	if index < 0 {
		index = length + index + 1
	}

	return max(0, min(index, length))
}
