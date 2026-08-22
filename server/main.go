package main

import (
	"bufio"
	"fmt"
	"log"
	"net"
	"slices"
	"strings"
	"sync"
	"time"
)

// TODO:
// Save all bufs when os signal
// Filetree, maybe slice of nodes that include relative and abs path?
// Add abs and rel path to buffer
// Save buf
// Ignored files and dirs
// Permissons???

type Buffer struct {
	mu    sync.RWMutex
	lines []string
}

func main() {
	b := NewBuffer()
	b.SetLines(0, -1, []string{"Mustan", "kissan", "paksut", "posket"})

	hub := NewHub()
	go hub.Run()

	// TODO: Port, debug, ignored flags
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

	// Temp
	lines, _ := b.GetLines(0, -1)
	for _, l := range lines {
		client.send <- l
	}

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

		// Ping, pong :D
		if text == "kisu" {
			client.send <- "mirri"
			continue
		}

		// Broadcast to all other conns
		hub.broadcast <- Message{
			sender: conn,
			event:  text,
		}
	}

	if err := scanner.Err(); err != nil {
		log.Println(err)
	}
}

func NewBuffer() *Buffer {
	return &Buffer{
		lines: []string{""},
	}
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
