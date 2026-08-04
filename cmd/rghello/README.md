# rghello CLI

Go command-line client for Rube Goldberg Hello World.

Milestone 0 skeleton: prints its version and a "not implemented" notice.
The real CLI (`rghello run`, SSE result streaming, `--message`, exit codes)
arrives in Milestones 3 and 9.

## Commands

```bash
go build ./...      # compile
go test ./...       # unit tests (stdlib only)
go vet ./...        # static analysis
gofmt -l .          # format check
```

## Coverage

```bash
go test -coverprofile=out/coverage.out ./...
go tool cover -func=out/coverage.out
```

CI enforces a 90% line-coverage threshold.
