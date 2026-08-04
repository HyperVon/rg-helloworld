# vector-normalizer-go

Go vector normalization service (geometry -> normalized SVG, gRPC client to
the C# rasterizer).

Milestone 0 skeleton: prints its version and a "not implemented" notice.

## Commands

```bash
go build ./...      # compile
go test ./...       # unit tests (stdlib only)
go vet ./...        # static analysis
gofmt -l .          # format check
```

CI enforces a 90% line-coverage threshold via `go test -cover`.
