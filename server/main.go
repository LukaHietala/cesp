package main

import (
	"context"
	"flag"
	"net"
	"os"
	"os/signal"
	"path/filepath"
	"strings"
	"sync"
	"syscall"
)

type Server struct {
	listener net.Listener
	quit     chan struct{}
	wg       sync.WaitGroup
	// Holds all TCP connections
	hub *Hub
	// Holds buffers, and other non-tcp stuff
	session *Session
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
		rootDir = filepath.Clean(flag.Arg(0))
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
