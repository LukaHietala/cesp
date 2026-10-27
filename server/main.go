package main

import (
	"fmt"
)

func main() {
	flags := parseFlags()

	setupLogger(flags.Verbose)

	addr := fmt.Sprintf(":%d", flags.Port)
	s := NewServer(addr, flags.RootDir, flags.Ignored)
	s.Start()
}
