// Package rasterclient is the gRPC client to the C# rasterizer service
// (architecture sections 12 and Stage 4): a ten-second per-call deadline
// and retries for transient gRPC status codes only.
package rasterclient

import (
	"context"
	"fmt"
	"time"

	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/credentials/insecure"
	"google.golang.org/grpc/status"

	"rghello.dev/vector-normalizer/internal/rasterproto"
)

// DefaultDeadline is the per-call client deadline (section 12: initially
// ten seconds).
const DefaultDeadline = 10 * time.Second

const maxAttempts = 3

// transientCodes are the only status codes worth retrying; everything else
// (InvalidArgument, DeadlineExceeded, ...) fails the call immediately.
var transientCodes = map[codes.Code]bool{
	codes.Unavailable:       true,
	codes.ResourceExhausted: true,
	codes.Aborted:           true,
}

// Client wraps the generated Rasterizer stub with deadline and retry
// policy. It implements worker.Renderer.
type Client struct {
	conn     *grpc.ClientConn
	svc      rasterproto.RasterizerClient
	Deadline time.Duration
}

// New dials the rasterizer. Additional dial options (e.g. a bufconn dialer
// in tests) may be passed through.
func New(addr string, opts ...grpc.DialOption) (*Client, error) {
	allOpts := append([]grpc.DialOption{grpc.WithTransportCredentials(insecure.NewCredentials())}, opts...)
	conn, err := grpc.NewClient(addr, allOpts...)
	if err != nil {
		return nil, fmt.Errorf("rasterclient: dial %s: %w", addr, err)
	}
	return &Client{conn: conn, svc: rasterproto.NewRasterizerClient(conn), Deadline: DefaultDeadline}, nil
}

// Close releases the connection.
func (c *Client) Close() error {
	return c.conn.Close()
}

// Render sends one RenderGlyph request, retrying transient failures with a
// short backoff until the deadline budget or attempt cap is exhausted.
func (c *Client) Render(ctx context.Context, req *rasterproto.RenderGlyphRequest) (*rasterproto.RenderGlyphResponse, error) {
	deadline := c.Deadline
	if deadline <= 0 {
		deadline = DefaultDeadline
	}
	var lastErr error
	for attempt := 1; attempt <= maxAttempts; attempt++ {
		callCtx, cancel := context.WithTimeout(ctx, deadline)
		resp, err := c.svc.RenderGlyph(callCtx, req)
		cancel()
		if err == nil {
			return resp, nil
		}
		lastErr = err
		if ctx.Err() != nil || !isTransient(err) || attempt == maxAttempts {
			return nil, err
		}
		select {
		case <-ctx.Done():
			return nil, ctx.Err()
		case <-time.After(time.Duration(attempt) * 200 * time.Millisecond):
		}
	}
	return nil, lastErr
}

func isTransient(err error) bool {
	st, ok := status.FromError(err)
	if !ok {
		return false
	}
	return transientCodes[st.Code()]
}
