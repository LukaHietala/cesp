package main

import (
	"flag"
	"fmt"
	"log/slog"
	"maps"
	"os"
	"path/filepath"
	"strings"
	"time"
)

type Flags struct {
	Port    uint16
	Verbose bool
	Ignored map[string]bool
	RootDir string
}

var defaultIgnored = map[string]bool{
	".git":         true,
	".env":         true,
	"node_modules": true,
	"build":        true,
	".venv":        true,
	".vscode":      true,
	"venv":         true,
	"__pycache__":  true,
	// TODO: Take from .gitignore!
}

func parseFlags() Flags {
	portPtr := flag.Uint("port", 8080, "Port where the server runs on")
	ignorePtr := flag.String("ignore", "", "Comma separated directories or files to ignore")
	verbosePtr := flag.Bool("debug", false, "Enable verbose logging")

	flag.Usage = func() {
		fmt.Fprintf(flag.CommandLine.Output(), "Usage of %s:\n", os.Args[0])
		flag.PrintDefaults()
	}

	flag.Parse()

	rootDir := "."
	if flag.NArg() > 0 {
		rootDir = filepath.Clean(flag.Arg(0))
	}

	ignoredMap := make(map[string]bool)
	maps.Copy(ignoredMap, defaultIgnored)

	if *ignorePtr != "" {
		for v := range strings.SplitSeq(*ignorePtr, ",") {
			if trimmed := strings.TrimSpace(v); trimmed != "" {
				ignoredMap[trimmed] = true
			}
		}
	}

	return Flags{
		Port:    uint16(*portPtr),
		Verbose: *verbosePtr,
		Ignored: ignoredMap,
		RootDir: rootDir,
	}
}

func setupLogger(verbose bool) {
	level := slog.LevelInfo
	if verbose {
		level = slog.LevelDebug
	}

	opts := &slog.HandlerOptions{
		Level: level,
		ReplaceAttr: func(groups []string, a slog.Attr) slog.Attr {
			if a.Key == slog.TimeKey {
				t := a.Value.Time()
				return slog.String("time", t.Format(time.TimeOnly))
			}

			if a.Key == slog.LevelKey {
				return slog.String("level", strings.ToLower(a.Value.String()))
			}

			return a
		},
	}

	handler := slog.NewTextHandler(os.Stdout, opts)
	logger := slog.New(handler)

	slog.SetDefault(logger)
}
