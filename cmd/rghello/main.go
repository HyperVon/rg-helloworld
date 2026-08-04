package main

import (
	"fmt"
	"io"
	"os"

	"rghello.dev/rghello/internal/version"
)

var exit = os.Exit

func main() {
	exit(run(os.Args[1:], os.Stdout, os.Stderr))
}

func run(args []string, stdout, stderr io.Writer) int {
	if len(args) == 1 && args[0] == "version" {
		fmt.Fprintf(stdout, "rghello %s\n", version.Version)
		return 0
	}
	fmt.Fprintln(stderr, "rghello: Milestone 0 skeleton - functionality not implemented yet")
	fmt.Fprintln(stderr, "usage: rghello version")
	return 0
}
