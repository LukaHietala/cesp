package main

import (
	"fmt"
	"log"
	"net"
	"slices"
)

type Buffer struct {
	lines []string
}

func main() {
	b := NewBuffer()

	b.SetLines(0, 1, []string{"Mustan", "kissan", "paksut", "posket"})

	listener, err := net.Listen("tcp", ":8080")
	if err != nil {
		log.Fatal(err)
	}
	defer listener.Close()

	for {
		conn, err := listener.Accept()
		if err != nil {
			log.Println(err)
			continue
		}

		go handleConn(conn, b)
	}
}

func handleConn(conn net.Conn, b *Buffer) {
	defer conn.Close()

	lines, _ := b.GetLines(0, -1)

	for _, l := range lines {
		fmt.Fprintln(conn, l)
	}
}

func NewBuffer() *Buffer {
	return &Buffer{
		lines: []string{""},
	}
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

// Normalizes 0-based indexes (same in Neovim)
// -1, one past last index, for appending (slices allow this)
// -2, last line...
func normalizeIndex(index, length int) int {
	if index < 0 {
		index = length + index + 1
	}

	return max(0, min(index, length))
}
