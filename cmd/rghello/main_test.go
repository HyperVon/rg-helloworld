package main

import (
	"bytes"
	"os"
	"os/exec"
	"strings"
	"testing"
)

func TestVersionCommand(t *testing.T) {
	var stdout, stderr bytes.Buffer
	code := run([]string{"version"}, &stdout, &stderr)
	if code != 0 {
		t.Fatalf("run(version) exit code = %d, want 0", code)
	}
	if !strings.HasPrefix(stdout.String(), "rghello ") {
		t.Fatalf("stdout = %q, want prefix %q", stdout.String(), "rghello ")
	}
	if stderr.Len() != 0 {
		t.Fatalf("stderr = %q, want empty", stderr.String())
	}
}

func TestUnknownCommandUsesStderr(t *testing.T) {
	var stdout, stderr bytes.Buffer
	code := run([]string{"run"}, &stdout, &stderr)
	if code != 0 {
		t.Fatalf("run([]) exit code = %d, want 0", code)
	}
	if stdout.Len() != 0 {
		t.Fatalf("stdout = %q, want empty", stdout.String())
	}
	if !strings.Contains(stderr.String(), "Milestone 0") {
		t.Fatalf("stderr = %q, want Milestone 0 notice", stderr.String())
	}
}

func TestVersionCommandIgnoresExtraArgs(t *testing.T) {
	var stdout, stderr bytes.Buffer
	code := run([]string{"version", "extra"}, &stdout, &stderr)
	if code != 0 {
		t.Fatalf("exit code = %d, want 0", code)
	}
	if stdout.Len() != 0 {
		t.Fatalf("stdout = %q, want empty for non-version invocation", stdout.String())
	}
	if !strings.Contains(stderr.String(), "usage:") {
		t.Fatalf("stderr = %q, want usage line", stderr.String())
	}
}

type exitSignal struct{ code int }

func TestMainInvocation(t *testing.T) {
	if os.Getenv("RGHELLO_MAIN_HELPER") == "1" {
		os.Args = []string{"rghello", "version"}
		exit = func(code int) { panic(exitSignal{code: code}) }
		defer func() {
			if r := recover(); r != nil {
				if s, ok := r.(exitSignal); !ok || s.code != 0 {
					panic(r)
				}
			}
		}()
		main()
		return
	}
	cmd := exec.Command(os.Args[0], "-test.run=TestMainInvocation")
	cmd.Env = append(os.Environ(), "RGHELLO_MAIN_HELPER=1")
	if profile := os.Getenv("RGHELLO_CHILD_COVER"); profile != "" {
		cmd.Args = append(cmd.Args, "-test.coverprofile="+profile)
	}
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("main() exited with error: %v (output: %q)", err, out)
	}
	if !strings.HasPrefix(string(out), "rghello 0.0.0-skeleton\n") {
		t.Fatalf("main() output = %q, want prefix %q", out, "rghello 0.0.0-skeleton\n")
	}
}
