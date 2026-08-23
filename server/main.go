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
// Save buf
// Ignored files and dirs
// SSH Tunnel (autossh like)
// JSON v2

type Buffer struct {
	mu    sync.RWMutex
	path  string
	lines []string
}

func main() {
	b := NewBuffer("asdf")
	b.SetLines(0, -1, []string{"Mustan", "kissan", "paksut", "posket"})

	// TCP connection hub
	hub := NewHub()
	go hub.Run()

	// Shared dir
	rootDir := "."
	fsys := os.DirFS(rootDir)

	// Make sure fsys is valid
	_, err := GetFiles(fsys)
	if err != nil {
		log.Fatal(err)
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

		go handleConn(conn, b, hub)
	}
}

func handleConn(conn net.Conn, b *Buffer, hub *Hub) {
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

		var msg EventUpdate
		err := json.Unmarshal([]byte(text), &msg)
		if err != nil {
			log.Println("Invalid JSON payload:", err)
			// TODO: complain to client
			continue
		}

		switch msg.Event {
		case "update_content":
			b.SetLines(
				msg.Changes.First,
				msg.Changes.OldLast,
				msg.Changes.Lines,
			)
		}

		lines, _ := b.GetLines(0, -1)
		content := strings.Join(lines, "\n")

		// Broadcast to all other conns
		hub.broadcast <- Message{
			sender: conn,
			event:  content,
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

func NewBuffer(path string) *Buffer {
	return &Buffer{
		path:  path,
		lines: []string{""},
	}
}

// Saves buffer to path relative to root
// dirFs is readonly so root path is used directly
func (b *Buffer) SaveBuffer(rootDir string) error {
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
