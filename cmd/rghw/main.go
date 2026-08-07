package main

import (
	"bufio"
	"context"
	"crypto/rand"
	_ "embed"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"strings"
	"time"

	"rghw.dev/rghw/internal/brainfuck"
	"rghw.dev/rghw/internal/version"
)

const (
	defaultAPIScheme = "http"
	defaultAPIHost   = "localhost:8080"

	exitSuccess = 0
	exitSystem  = 1
	exitInvalid = 2
	exitTimeout = 3
)

type runOptions struct {
	message string
	apiURL  string
	timeout time.Duration
	quiet   bool
}

type createRunResponse struct {
	RunID string `json:"runId"`
}

type streamEvent struct {
	Status        string `json:"status"`
	AssembledText string `json:"assembledText,omitempty"`
}

//go:embed internal/brainfuck/default.bf
var brainfuckDefaultProgram string

func decodeDefaultMessage() string {
	vm := brainfuck.NewVM([]byte(brainfuckDefaultProgram))
	out, err := vm.Run()
	if err != nil {
		return ""
	}
	return string(out)
}

func newRunOptions() runOptions {
	return runOptions{
		message: decodeDefaultMessage(),
		apiURL:  defaultAPIScheme + "://" + defaultAPIHost,
		timeout: 3 * time.Minute,
	}
}

func parseRunArgs(args []string) (runOptions, error) {
	opts := newRunOptions()
	for i := 0; i < len(args); i++ {
		arg := args[i]
		switch {
		case arg == "--message":
			if i+1 >= len(args) {
				return opts, errors.New("--message requires a value")
			}
			i++
			opts.message = args[i]
		case strings.HasPrefix(arg, "--message="):
			opts.message = strings.TrimPrefix(arg, "--message=")
		case arg == "--api-url":
			if i+1 >= len(args) {
				return opts, errors.New("--api-url requires a value")
			}
			i++
			opts.apiURL = strings.TrimSuffix(args[i], "/")
		case strings.HasPrefix(arg, "--api-url="):
			opts.apiURL = strings.TrimSuffix(strings.TrimPrefix(arg, "--api-url="), "/")
		case arg == "--timeout":
			if i+1 >= len(args) {
				return opts, errors.New("--timeout requires a value")
			}
			i++
			duration, err := time.ParseDuration(args[i])
			if err != nil {
				return opts, fmt.Errorf("invalid --timeout %q: %w", args[i], err)
			}
			opts.timeout = duration
		case strings.HasPrefix(arg, "--timeout="):
			duration, err := time.ParseDuration(strings.TrimPrefix(arg, "--timeout="))
			if err != nil {
				return opts, fmt.Errorf("invalid --timeout %q: %w", arg, err)
			}
			opts.timeout = duration
		case arg == "--quiet":
			opts.quiet = true
		default:
			return opts, fmt.Errorf("unknown argument %q", arg)
		}
	}
	if opts.message == "" {
		return opts, errors.New("--message must not be empty")
	}
	return opts, nil
}

func run(args []string, stdout, stderr io.Writer) int {
	if len(args) >= 1 && args[0] == "version" {
		return runVersion(args[1:], stdout, stderr)
	}
	if len(args) >= 1 && args[0] == "run" {
		return runRun(context.Background(), args[1:], stdout, stderr)
	}
	fmt.Fprintln(stderr, "rghw: unknown command")
	fmt.Fprintln(stderr, "usage: rghw run [--message TEXT] [--api-url URL] [--timeout DURATION] [--quiet]")
	return exitInvalid
}

func runRun(ctx context.Context, args []string, stdout, stderr io.Writer) int {
	opts, err := parseRunArgs(args)
	if err != nil {
		fmt.Fprintf(stderr, "rghw: %v\n", err)
		return exitInvalid
	}
	client := &http.Client{Timeout: opts.timeout}
	ctx, cancel := context.WithTimeout(ctx, opts.timeout)
	defer cancel()

	if !opts.quiet {
		fmt.Fprintln(stderr, "[1/2] Creating run...")
	}
	runID, err := createRun(ctx, client, opts.apiURL, opts.message)
	if err != nil {
		fmt.Fprintf(stderr, "rghw: %v\n", err)
		if isTimeout(err) {
			return exitTimeout
		}
		return exitSystem
	}

	if !opts.quiet {
		fmt.Fprintln(stderr, "[2/2] Waiting for the orchestrator...")
	}
	result, err := streamResult(ctx, client, opts.apiURL, runID)
	if err != nil {
		fmt.Fprintf(stderr, "rghw: %v\n", err)
		if isTimeout(err) {
			return exitTimeout
		}
		return exitSystem
	}
	fmt.Fprintf(stdout, "%s\n", result)
	return exitSuccess
}

func isTimeout(err error) bool {
	if errors.Is(err, context.DeadlineExceeded) {
		return true
	}
	var netErr net.Error
	return errors.As(err, &netErr) && netErr.Timeout()
}

func createRun(ctx context.Context, client *http.Client, baseURL, message string) (string, error) {
	body, err := json.Marshal(map[string]string{"message": message})
	if err != nil {
		return "", err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, baseURL+"/api/v1/runs", strings.NewReader(string(body)))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Idempotency-Key", newRunID())

	resp, err := client.Do(req)
	if err != nil {
		return "", fmt.Errorf("create run: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusAccepted {
		return "", fmt.Errorf("create run: unexpected status %d", resp.StatusCode)
	}
	var created createRunResponse
	if err := json.NewDecoder(resp.Body).Decode(&created); err != nil {
		return "", fmt.Errorf("create run: decode response: %w", err)
	}
	if created.RunID == "" {
		return "", errors.New("create run: response missing runId")
	}
	return created.RunID, nil
}

func streamResult(ctx context.Context, client *http.Client, baseURL, runID string) (string, error) {
	streamURL, err := url.Parse(baseURL + "/api/v1/runs/" + runID + "/stream")
	if err != nil {
		return "", err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, streamURL.String(), nil)
	if err != nil {
		return "", err
	}
	resp, err := client.Do(req)
	if err != nil {
		return "", fmt.Errorf("stream: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("stream: unexpected status %d", resp.StatusCode)
	}
	return parseSSE(ctx, resp.Body)
}

func parseSSE(ctx context.Context, body io.Reader) (string, error) {
	scanner := bufio.NewScanner(body)
	firstLine := true
	for scanner.Scan() {
		select {
		case <-ctx.Done():
			return "", ctx.Err()
		default:
		}
		line := scanner.Text()
		if firstLine {
			if err := brainfuck.VerifyIntegrity([]byte(line)); err != nil {
				return "", fmt.Errorf("stream: integrity check failed: %w", err)
			}
			firstLine = false
		}
		if line == "" || strings.HasPrefix(line, ":") {
			continue
		}
		if !strings.HasPrefix(line, "data: ") {
			continue
		}
		var event streamEvent
		if err := json.Unmarshal([]byte(strings.TrimPrefix(line, "data: ")), &event); err != nil {
			continue
		}
		if event.Status == "SUCCEEDED" && event.AssembledText != "" {
			return event.AssembledText, nil
		}
		if event.Status == "FAILED" {
			return "", errors.New("run failed")
		}
	}
	if err := scanner.Err(); err != nil {
		return "", fmt.Errorf("stream: %w", err)
	}
	return "", errors.New("stream closed without a terminal event")
}

func newRunID() string {
	var id [16]byte
	if _, err := rand.Read(id[:]); err != nil {
		return fmt.Sprintf("%x", time.Now().UnixNano())
	}
	id[6] = (id[6] & 0x0f) | 0x40
	id[8] = (id[8] & 0x3f) | 0x80
	return fmt.Sprintf("%x-%x-%x-%x-%x", id[0:4], id[4:6], id[6:8], id[8:10], id[10:16])
}

var exit = os.Exit

func runVersion(args []string, stdout, stderr io.Writer) int {
	fmt.Fprintf(stdout, "rghw %s\n", version.Version)
	if len(args) > 0 {
		fmt.Fprintln(stderr, "rghw: version ignores extra arguments")
	}
	return exitSuccess
}

func main() {
	exit(run(os.Args[1:], os.Stdout, os.Stderr))
}
