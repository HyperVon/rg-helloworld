# rghw CLI

Go command-line client for Rube Goldberg Hello World.

Milestone 12: `rghw run` submits a phrase to the orchestrator over REST,
streams SSE updates, and prints the final assembled text to stdout.

## Commands

```bash
go build ./...      # compile
go test ./...       # unit tests (stdlib only)
go vet ./...        # static analysis
gofmt -l .          # format check
```

## Usage

```bash
rghw run
rghw run --message "<obfuscated phrase>"
rghw run --api-url http://localhost:8080 --timeout 3m
rghw run --quiet
```

`rghw run` writes progress to stderr and prints only the resulting phrase
to stdout. Exit codes: 0 success, 2 invalid request, 3 timeout, 1 system
failure.

## Coverage

```bash
go test -coverprofile=out/coverage.out ./...
go tool cover -func=out/coverage.out
```

CI enforces a 90% line-coverage threshold.
