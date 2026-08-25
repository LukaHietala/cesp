package main

import (
	"bufio"
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"io/fs"
	"log"
	"net"
	"os"
	"os/signal"
	"path/filepath"
	"slices"
	"strings"
	"sync"
	"syscall"
	"time"
)

// TODO:
// Save all bufs when os signal
// SSH Tunnel (autossh like)
// JSON v2

type Server struct {
	listener net.Listener
	quit     chan struct{}
	wg       sync.WaitGroup
	// Holds all TCP connections
	hub *Hub
	// Holds buffers, and other non-tcp stuff
	session *Session
}

type Session struct {
	// Open buffers
	buffers sync.Map
	// Readonly fs for project files
	fsys fs.FS
	// Path to project files
	rootDir string
	// Map of ignored dirs
	ignoredDirs map[string]bool
}

type Buffer struct {
	mu sync.RWMutex
	// Path in fsys to file
	path string
	// Content
	lines []string
}

// TODO: files too
var defaultIgnoredDirs = []string{
	".git", "node_modules", "build", ".venv", ".vscode", "venv", "__pycache__",
}

func parseArgs() (port string, rootDir string, ignoredDirs map[string]bool) {
	portPtr := flag.String("port", "8080", "Port to run the server on")
	ignorePtr := flag.String("ignore", "", "Comma separated extra dirs to ignore")
	flag.Parse()

	if rootDir == "" {
		rootDir = "."
	}

	if flag.NArg() > 0 {
		rootDir = flag.Arg(0)
	}

	ignoredDirs = make(map[string]bool, len(defaultIgnoredDirs))
	for _, v := range defaultIgnoredDirs {
		ignoredDirs[v] = true
	}

	if *ignorePtr != "" {
		for v := range strings.SplitSeq(*ignorePtr, ",") {
			if trimmed := strings.TrimSpace(v); trimmed != "" {
				ignoredDirs[trimmed] = true
			}
		}
	}

	return *portPtr, rootDir, ignoredDirs
}

func main() {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	port, rootDir, ignoredDirs := parseArgs()

	addr := ":" + port
	s := NewServer(addr, rootDir, ignoredDirs)

	<-ctx.Done()
	s.Stop()
	os.Exit(0)
}

func NewServer(addr, rootDir string, ignoredDirs map[string]bool) *Server {
	s := &Server{
		quit: make(chan struct{}),
	}

	listener, err := net.Listen("tcp", addr)
	if err != nil {
		log.Fatal(err)
	}

	hub := NewHub()
	go hub.Run()

	fsys := os.DirFS(rootDir)

	session := &Session{
		fsys:        fsys,
		rootDir:     rootDir,
		ignoredDirs: ignoredDirs,
	}

	s.listener = listener
	s.hub = hub
	s.session = session

	s.wg.Add(1)
	go s.serve()

	return s
}

func (s *Server) Stop() {
	// Signals to all goroutines to die
	close(s.quit)
	// Stop accepting new connections
	s.listener.Close()
	// Closes all existing connections
	s.hub.Stop()
	// Wait for everything to cleanup
	s.wg.Wait()
}

func (s *Server) serve() {
	defer s.wg.Done()
	log.Println("Listening on", s.listener.Addr().String())

	for {
		conn, err := s.listener.Accept()
		if err != nil {
			select {
			case <-s.quit:
				return
			default:
				log.Println("accept error", err)
			}
			continue
		}

		go s.handleConnection(conn)
	}
}

func (s *Server) handleConnection(conn net.Conn) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	client := &Client{
		conn: conn,
		send: make(chan any, 100),
	}

	s.hub.register <- client

	defer func() {
		s.hub.unregister <- client
		conn.Close()
		log.Println("Connection closed", conn.RemoteAddr())
	}()

	log.Println("New connection", conn.RemoteAddr())

	// Write pump
	go func() {
		encoder := json.NewEncoder(conn)
		for {
			select {
			case <-ctx.Done():
				// Read pump exited or write failed so die
				return
			case msg, ok := <-client.send:
				if !ok {
					return
				}
				conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
				err := encoder.Encode(msg)
				if err != nil {
					log.Println("write error", err)
					cancel()
					return
				}
			}
		}
	}()

	// Max 5MB buffer
	const maxCap = 1024 * 1024 * 5
	scanner := bufio.NewScanner(conn)
	buf := make([]byte, maxCap)
	scanner.Buffer(buf, maxCap)

	// Read pump
	for scanner.Scan() {
		// If write is broken die
		if ctx.Err() != nil {
			break
		}

		conn.SetReadDeadline(time.Now().Add(5 * time.Minute))

		text := strings.TrimSpace(scanner.Text())
		if text == "" {
			continue
		}

		log.Println("Received", text)

		var msg EventMessage
		err := json.Unmarshal([]byte(text), &msg)
		if err != nil {
			log.Printf("Invalid JSON payload from %s: %v\n", conn.RemoteAddr(), err)
			continue
		}

		err = s.handleEvent(msg, client, conn)
		if err != nil {
			log.Println("event error", err)
		}
	}

	if err := scanner.Err(); err != nil {
		log.Println(err)
	}
}

func (s *Server) handleEvent(msg EventMessage, client *Client, conn net.Conn) error {
	switch msg.Event {
	case "request_files":
		files, err := GetFiles(s.session.fsys, s.session.ignoredDirs)
		if err != nil {
			return err
		}

		client.send <- ResponseFiles{
			Event: "response_files",
			Files: files,
		}

	case "request_file":
		b := s.session.GetBuffer(msg.Path)
		lines, _ := b.GetLines(0, -1)

		client.send <- ResponseFile{
			Event:   "response_file",
			Path:    msg.Path,
			Content: strings.Join(lines, "\n"),
		}

	case "update_content":
		if msg.Changes == nil {
			return fmt.Errorf("update_content missing changes")
		}

		b := s.session.GetBuffer(msg.Path)
		b.SetLines(
			msg.Changes.First,
			msg.Changes.OldLast,
			msg.Changes.Lines,
		)

		s.hub.broadcast <- Message{
			sender:  conn,
			payload: msg,
		}

	case "remote_write":
		b := s.session.GetBuffer(msg.Path)
		err := b.Save(s.session.rootDir)
		if err != nil {
			log.Printf("Error saving %s: %v\n", msg.Path, err)
		}
		log.Printf("Saved %s\n", msg.Path)

	case "":
		return fmt.Errorf("empty event")

	default:
		// Just forward if nothing needs to be done
		// Maybe not wise if invalid event but that's the clients problem now
		s.hub.broadcast <- Message{
			sender:  conn,
			payload: msg,
		}
	}

	return nil
}

func GetFiles(fsys fs.FS, ignoredDirs map[string]bool) ([]string, error) {
	var paths []string

	err := fs.WalkDir(fsys, ".", func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() {
			if ignoredDirs[d.Name()] {
				return fs.SkipDir
			}
			return nil
		}

		paths = append(paths, path)
		return nil
	})

	return paths, err
}

// GetBuffer returns an existing buffer for the path, or creates a new one
func (s *Session) GetBuffer(path string) *Buffer {
	// Try to get open buffer
	if v, ok := s.buffers.Load(path); ok {
		return v.(*Buffer)
	}

	// If not found create a new one
	b := NewBuffer(path)
	// Populate with files contents, defaults to empty slice
	content, err := fs.ReadFile(s.fsys, path)
	if err == nil {
		lines := strings.Split(string(content), "\n")
		b.SetLines(0, -1, lines)
	}

	// Thread-safe (sync map)
	actual, _ := s.buffers.LoadOrStore(path, b)
	return actual.(*Buffer)
}

func NewBuffer(path string) *Buffer {
	return &Buffer{
		path: path,
		// Lines must never be empty
		lines: []string{""},
	}
}

// Save saves a buffer
func (b *Buffer) Save(rootDir string) error {
	b.mu.RLock()
	defer b.mu.RUnlock()

	// Rotanloukku
	if !fs.ValidPath(b.path) {
		return fmt.Errorf("illegal path %s", b.path)
	}

	cleanRoot := filepath.Clean(rootDir)
	fullPath := filepath.Join(cleanRoot, b.path)

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
