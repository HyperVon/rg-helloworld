package main

import (
	"fmt"
	"io"
	"os"

	"rghello.dev/vector-normalizer/internal/version"
)

var exit = os.Exit

func main() {
	exit(run(os.Args[1:], os.Stdout, os.Stderr))
}

func run(args []string, stdout, stderr io.Writer) int {
	if len(args) == 1 && args[0] == "version" {
		fmt.Fprintf(stdout, "vector-normalizer %s\n", version.Version)
		return 0
	}
	fmt.Fprintln(stderr, "vector-normalizer: Milestone 0 skeleton - functionality not implemented yet")
	fmt.Fprintln(stderr, "usage: vector-normalizer version")
	return 0
}
