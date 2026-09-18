package main

import (
	"context"
	"flag"
	"os"
	"os/signal"
	"path/filepath"
	"strings"
	"syscall"
)

func main() {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	port, rootDir, ignoredDirs := parseArgs()

	addr := ":" + port
	s := NewServer(rootDir, ignoredDirs)
	s.Start(addr)

	<-ctx.Done()
	s.Stop()
	os.Exit(0)
}

var defaultIgnored = []string{
	".git", ".env", "node_modules", "build", ".venv", ".vscode", "venv", "__pycache__",
}

func parseArgs() (port string, rootDir string, ignored []string) {
	portPtr := flag.String("port", "8080", "Port to run the server on")
	ignorePtr := flag.String("ignore", "", "Comma separated dirs or files to ignore")
	flag.Parse()

	if rootDir == "" {
		rootDir = "."
	}

	if flag.NArg() > 0 {
		rootDir = filepath.Clean(flag.Arg(0))
	}

	ignored = defaultIgnored

	if *ignorePtr != "" {
		for v := range strings.SplitSeq(*ignorePtr, ",") {
			if trimmed := strings.TrimSpace(v); trimmed != "" {
				ignored = append(ignored, trimmed)
			}
		}
	}

	return *portPtr, rootDir, ignored
}
