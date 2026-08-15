package main

import (
	"bytes"
	"context"
	"net/http"
	"net/http/httptest"
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
	if !strings.HasPrefix(stdout.String(), "rghw ") {
		t.Fatalf("stdout = %q, want prefix %q", stdout.String(), "rghw ")
	}
	if stderr.Len() != 0 {
		t.Fatalf("stderr = %q, want empty", stderr.String())
	}
}

func TestVersionCommandIgnoresExtraArgs(t *testing.T) {
	var stdout, stderr bytes.Buffer
	code := run([]string{"version", "extra"}, &stdout, &stderr)
	if code != 0 {
		t.Fatalf("exit code = %d, want 0", code)
	}
	if !strings.HasPrefix(stdout.String(), "rghw ") {
		t.Fatalf("stdout = %q, want version prefix", stdout.String())
	}
}

func TestUnknownCommandUsesStderr(t *testing.T) {
	var stdout, stderr bytes.Buffer
	code := run([]string{"bogus"}, &stdout, &stderr)
	if code != exitInvalid {
		t.Fatalf("run(bogus) exit code = %d, want %d", code, exitInvalid)
	}
	if stdout.Len() != 0 {
		t.Fatalf("stdout = %q, want empty", stdout.String())
	}
	if !strings.Contains(stderr.String(), "usage:") {
		t.Fatalf("stderr = %q, want usage line", stderr.String())
	}
}

func TestRunCommandHappyPath(t *testing.T) {
	var created bool
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case r.Method == http.MethodPost && r.URL.Path == "/api/v1/runs":
			created = true
			if r.Header.Get("Idempotency-Key") == "" {
				t.Error("missing Idempotency-Key header")
			}
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusAccepted)
			_, _ = w.Write([]byte(`{"runId":"run-123","status":"PLANNING","createdAt":"2026-01-01T00:00:00Z","links":{"self":"/api/v1/runs/run-123","events":"/api/v1/runs/run-123/events","stream":"/api/v1/runs/run-123/stream","artifacts":"/api/v1/runs/run-123/artifacts"}}`))
		case r.Method == http.MethodGet && r.URL.Path == "/api/v1/runs/run-123/stream":
			w.Header().Set("Content-Type", "text/event-stream")
			_, _ = w.Write([]byte(": connected\n\nid: run-123\nevent: step-status-changed\ndata: {\"status\":\"PLANNING\"}\n\nid: run-123\nevent: run-succeeded\ndata: {\"status\":\"SUCCEEDED\",\"assembledText\":\"HELLO WORLD\"}\n\n"))
		default:
			t.Errorf("unexpected request: %s %s", r.Method, r.URL.Path)
			w.WriteHeader(http.StatusNotFound)
		}
	}))
	defer server.Close()

	var stdout, stderr bytes.Buffer
	code := runRun(context.Background(), []string{"--api-url", server.URL, "--quiet"}, &stdout, &stderr)

	if code != exitSuccess {
		t.Fatalf("exit code = %d, want %d (stderr: %s)", code, exitSuccess, stderr.String())
	}
	if !created {
		t.Fatal("run was not created")
	}
	if stdout.String() != "HELLO WORLD\n" {
		t.Fatalf("stdout = %q, want %q", stdout.String(), "HELLO WORLD\n")
	}
}

func TestRunCommandPrintsProgressToStderrUnlessQuiet(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case r.Method == http.MethodPost:
			w.WriteHeader(http.StatusAccepted)
			_, _ = w.Write([]byte(`{"runId":"run-123","status":"PLANNING","createdAt":"2026-01-01T00:00:00Z","links":{"self":"","events":"","stream":"","artifacts":""}}`))
		case r.Method == http.MethodGet:
			_, _ = w.Write([]byte(": connected\n\ndata: {\"status\":\"SUCCEEDED\",\"assembledText\":\"Hi\"}\n\n"))
		}
	}))
	defer server.Close()

	var stdout, stderr bytes.Buffer
	code := runRun(context.Background(), []string{"--api-url", server.URL, "--message", "Hi"}, &stdout, &stderr)

	if code != exitSuccess {
		t.Fatalf("exit code = %d, want %d", code, exitSuccess)
	}
	if !strings.Contains(stderr.String(), "[1/2]") || !strings.Contains(stderr.String(), "[2/2]") {
		t.Fatalf("stderr = %q, want progress lines", stderr.String())
	}
	if stdout.String() != "Hi\n" {
		t.Fatalf("stdout = %q, want %q", stdout.String(), "Hi\n")
	}
}

func TestRunCommandFailsOnInvalidMessage(t *testing.T) {
	var stdout, stderr bytes.Buffer
	code := runRun(context.Background(), []string{"--message", ""}, &stdout, &stderr)
	if code != exitInvalid {
		t.Fatalf("exit code = %d, want %d", code, exitInvalid)
	}
}

func TestRunCommandHandlesCreateRejection(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusBadRequest)
	}))
	defer server.Close()

	var stdout, stderr bytes.Buffer
	code := runRun(context.Background(), []string{"--api-url", server.URL, "--quiet"}, &stdout, &stderr)
	if code != exitSystem {
		t.Fatalf("exit code = %d, want %d", code, exitSystem)
	}
	if stdout.Len() != 0 {
		t.Fatalf("stdout = %q, want empty", stdout.String())
	}
}

func TestParseSSEStopsAtFirstTerminalEvent(t *testing.T) {
	body := ": connected\n\ndata: {\"status\":\"PLANNING\"}\n\ndata: {\"status\":\"SUCCEEDED\",\"assembledText\":\"Done\"}\n\ndata: {\"status\":\"SUCCEEDED\",\"assembledText\":\"Ignored\"}\n"
	result, err := parseSSE(context.Background(), strings.NewReader(body))
	if err != nil {
		t.Fatalf("parseSSE error: %v", err)
	}
	if result != "Done" {
		t.Fatalf("result = %q, want %q", result, "Done")
	}
}

func TestParseSSEFailedRun(t *testing.T) {
	body := "data: {\"status\":\"FAILED\"}\n"
	_, err := parseSSE(context.Background(), strings.NewReader(body))
	if err == nil || !strings.Contains(err.Error(), "failed") {
		t.Fatalf("parseSSE error = %v, want failure", err)
	}
}

func TestParseSSEClosedWithoutTerminalEvent(t *testing.T) {
	body := "data: {\"status\":\"PLANNING\"}\n"
	_, err := parseSSE(context.Background(), strings.NewReader(body))
	if err == nil {
		t.Fatal("parseSSE error = nil, want closed-without-event error")
	}
}

func TestParseRunArgsDefaults(t *testing.T) {
	opts, err := parseRunArgs(nil)
	if err != nil {
		t.Fatalf("parseRunArgs error: %v", err)
	}
	if opts.message != "HELLO WORLD" {
		t.Fatalf("message = %q, want default", opts.message)
	}
	if opts.apiURL != "http://localhost:8080" {
		t.Fatalf("apiURL = %q, want default", opts.apiURL)
	}
	if opts.timeout.String() != "3m0s" {
		t.Fatalf("timeout = %q, want 3m0s", opts.timeout)
	}
}

func TestParseRunArgsOverrides(t *testing.T) {
	opts, err := parseRunArgs([]string{
		"--message", "Hi there",
		"--api-url", "http://orch:9090/",
		"--timeout", "10s",
		"--quiet",
	})
	if err != nil {
		t.Fatalf("parseRunArgs error: %v", err)
	}
	if opts.message != "Hi there" {
		t.Fatalf("message = %q, want override", opts.message)
	}
	if opts.apiURL != "http://orch:9090" {
		t.Fatalf("apiURL = %q, want trailing slash trimmed", opts.apiURL)
	}
	if opts.timeout.String() != "10s" {
		t.Fatalf("timeout = %q, want 10s", opts.timeout)
	}
	if !opts.quiet {
		t.Fatal("quiet = false, want true")
	}
}

func TestParseRunArgsRejectsUnknownFlag(t *testing.T) {
	_, err := parseRunArgs([]string{"--bogus"})
	if err == nil {
		t.Fatal("parseRunArgs error = nil, want unknown argument error")
	}
}

func TestParseRunArgsRejectsBadTimeout(t *testing.T) {
	_, err := parseRunArgs([]string{"--timeout", "not-a-duration"})
	if err == nil {
		t.Fatal("parseRunArgs error = nil, want bad timeout error")
	}
}

func TestParseRunArgsMissingValues(t *testing.T) {
	for _, args := range [][]string{
		{"--message"},
		{"--api-url"},
		{"--timeout"},
	} {
		if _, err := parseRunArgs(args); err == nil {
			t.Fatalf("parseRunArgs(%v) error = nil, want missing value error", args)
		}
	}
}

func TestParseRunArgsEqualsForms(t *testing.T) {
	opts, err := parseRunArgs([]string{
		"--message=Equals form",
		"--api-url=http://orch:8080/",
		"--timeout=5s",
	})
	if err != nil {
		t.Fatalf("parseRunArgs error: %v", err)
	}
	if opts.message != "Equals form" {
		t.Fatalf("message = %q, want equals form value", opts.message)
	}
	if opts.apiURL != "http://orch:8080" {
		t.Fatalf("apiURL = %q, want trailing slash trimmed", opts.apiURL)
	}
	if opts.timeout.String() != "5s" {
		t.Fatalf("timeout = %q, want 5s", opts.timeout)
	}
}

func TestRunDispatchToRunCommand(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case r.Method == http.MethodPost:
			w.WriteHeader(http.StatusAccepted)
			_, _ = w.Write([]byte(`{"runId":"run-123","status":"PLANNING","createdAt":"2026-01-01T00:00:00Z","links":{"self":"","events":"","stream":"","artifacts":""}}`))
		case r.Method == http.MethodGet:
			_, _ = w.Write([]byte(": connected\n\ndata: {\"status\":\"SUCCEEDED\",\"assembledText\":\"HELLO WORLD\"}\n"))
		}
	}))
	defer server.Close()

	var stdout, stderr bytes.Buffer
	code := run([]string{"run", "--quiet", "--api-url", server.URL}, &stdout, &stderr)
	if code != exitSuccess {
		t.Fatalf("exit code = %d, want %d (stderr: %s)", code, exitSuccess, stderr.String())
	}
	if stdout.String() != "HELLO WORLD\n" {
		t.Fatalf("stdout = %q, want %q", stdout.String(), "HELLO WORLD\n")
	}
}

func TestRunCommandTimesOut(t *testing.T) {
	release := make(chan struct{})
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodPost {
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusAccepted)
			_, _ = w.Write([]byte(`{"runId":"run-123","status":"PLANNING","createdAt":"2026-01-01T00:00:00Z","links":{"self":"","events":"","stream":"","artifacts":""}}`))
			return
		}
		w.Header().Set("Content-Type", "text/event-stream")
		w.WriteHeader(http.StatusOK)
		flusher, _ := w.(http.Flusher)
		if flusher != nil {
			flusher.Flush()
		}
		<-release
	}))
	defer func() {
		close(release)
		server.Close()
	}()

	var stdout, stderr bytes.Buffer
	code := runRun(context.Background(), []string{"--api-url", server.URL, "--quiet", "--timeout", "50ms"}, &stdout, &stderr)
	if code != exitTimeout {
		t.Fatalf("exit code = %d, want %d (stderr: %s)", code, exitTimeout, stderr.String())
	}
	if stdout.Len() != 0 {
		t.Fatalf("stdout = %q, want empty", stdout.String())
	}
}

func TestCreateRunConnectionFailure(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {}))
	server.Close()

	_, err := createRun(context.Background(), server.Client(), server.URL, "HELLO WORLD")
	if err == nil {
		t.Fatal("createRun error = nil, want connection error")
	}
}

func TestCreateRunDecodeFailure(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusAccepted)
		_, _ = w.Write([]byte("not-json"))
	}))
	defer server.Close()

	_, err := createRun(context.Background(), server.Client(), server.URL, "HELLO WORLD")
	if err == nil {
		t.Fatal("createRun error = nil, want decode error")
	}
}

func TestCreateRunMissingRunID(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusAccepted)
		_, _ = w.Write([]byte(`{"status":"PLANNING"}`))
	}))
	defer server.Close()

	_, err := createRun(context.Background(), server.Client(), server.URL, "HELLO WORLD")
	if err == nil {
		t.Fatal("createRun error = nil, want missing runId error")
	}
}

func TestStreamResultRejectsNonOK(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
	}))
	defer server.Close()

	_, err := streamResult(context.Background(), server.Client(), server.URL, "run-1")
	if err == nil {
		t.Fatal("streamResult error = nil, want status error")
	}
}

func TestParseSSESkipsMalformedData(t *testing.T) {
	body := "data: {not json\n\ndata: {\"status\":\"SUCCEEDED\",\"assembledText\":\"Ok\"}\n"
	result, err := parseSSE(context.Background(), strings.NewReader(body))
	if err != nil {
		t.Fatalf("parseSSE error: %v", err)
	}
	if result != "Ok" {
		t.Fatalf("result = %q, want %q", result, "Ok")
	}
}

func TestNewRunIDIsUUIDShaped(t *testing.T) {
	id := newRunID()
	if len(id) != 36 {
		t.Fatalf("run id = %q, want 36 chars", id)
	}
}

type exitSignal struct{ code int }

func TestMainInvocation(t *testing.T) {
	if os.Getenv("RGHW_MAIN_HELPER") == "1" {
		os.Args = []string{"rghw", "version"}
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
	cmd.Env = append(os.Environ(), "RGHW_MAIN_HELPER=1")
	if profile := os.Getenv("RGHW_CHILD_COVER"); profile != "" {
		cmd.Args = append(cmd.Args, "-test.coverprofile="+profile)
	}
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("main() exited with error: %v (output: %q)", err, out)
	}
	if !strings.HasPrefix(string(out), "rghw ") {
		t.Fatalf("main() output = %q, want version prefix", out)
	}
}
