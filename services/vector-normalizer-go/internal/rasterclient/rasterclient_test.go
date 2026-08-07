package rasterclient

import (
	"context"
	"net"
	"sync"
	"testing"
	"time"

	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/credentials/insecure"
	"google.golang.org/grpc/status"
	"google.golang.org/grpc/test/bufconn"

	"rghw.dev/vector-normalizer/internal/rasterproto"
)

type stepResult struct {
	resp *rasterproto.RenderGlyphResponse
	err  error
}

func okStep(resp *rasterproto.RenderGlyphResponse) stepResult { return stepResult{resp: resp} }
func errStep(err error) stepResult                            { return stepResult{err: err} }

type fakeRasterizerServer struct {
	rasterproto.UnimplementedRasterizerServer
	mu    sync.Mutex
	calls int
	plan  []stepResult
	sleep time.Duration
}

func (f *fakeRasterizerServer) RenderGlyph(_ context.Context, _ *rasterproto.RenderGlyphRequest) (*rasterproto.RenderGlyphResponse, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.calls++
	if f.sleep > 0 {
		time.Sleep(f.sleep)
	}
	index := f.calls - 1
	if index < len(f.plan) {
		step := f.plan[index]
		if step.err != nil {
			return nil, step.err
		}
		if step.resp != nil {
			return step.resp, nil
		}
	}
	return &rasterproto.RenderGlyphResponse{ObjectKey: "ok", Sha256: "00"}, nil
}

func (f *fakeRasterizerServer) callCount() int {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.calls
}

func newTestClient(t *testing.T, server rasterproto.RasterizerServer, deadline time.Duration) *Client {
	t.Helper()
	listener := bufconn.Listen(1024 * 1024)
	grpcServer := grpc.NewServer()
	rasterproto.RegisterRasterizerServer(grpcServer, server)
	go func() { _ = grpcServer.Serve(listener) }()
	t.Cleanup(grpcServer.Stop)

	conn, err := grpc.NewClient("passthrough:///bufnet",
		grpc.WithContextDialer(func(ctx context.Context, _ string) (net.Conn, error) {
			return listener.DialContext(ctx)
		}),
		grpc.WithTransportCredentials(insecure.NewCredentials()))
	if err != nil {
		t.Fatalf("grpc client: %v", err)
	}
	t.Cleanup(func() { _ = conn.Close() })
	return &Client{conn: conn, svc: rasterproto.NewRasterizerClient(conn), Deadline: deadline}
}

func TestRenderReturnsResponse(t *testing.T) {
	server := &fakeRasterizerServer{plan: []stepResult{okStep(&rasterproto.RenderGlyphResponse{ObjectKey: "k.png", Width: 10, Height: 20})}}
	client := newTestClient(t, server, time.Second)

	response, err := client.Render(context.Background(), &rasterproto.RenderGlyphRequest{})
	if err != nil {
		t.Fatalf("Render: %v", err)
	}
	if response.ObjectKey != "k.png" || response.Width != 10 || response.Height != 20 {
		t.Fatalf("response = %+v", response)
	}
	if server.callCount() != 1 {
		t.Fatalf("calls = %d, want 1", server.callCount())
	}
}

func TestRenderRetriesTransientUnavailable(t *testing.T) {
	server := &fakeRasterizerServer{plan: []stepResult{
		errStep(status.Error(codes.Unavailable, "down")),
		okStep(&rasterproto.RenderGlyphResponse{ObjectKey: "recovered.png"}),
	}}
	client := newTestClient(t, server, time.Second)

	response, err := client.Render(context.Background(), &rasterproto.RenderGlyphRequest{})
	if err != nil {
		t.Fatalf("Render: %v", err)
	}
	if response.ObjectKey != "recovered.png" {
		t.Fatalf("response = %+v", response)
	}
	if server.callCount() != 2 {
		t.Fatalf("calls = %d, want 2 (retried once)", server.callCount())
	}
}

func TestRenderDoesNotRetryNonTransient(t *testing.T) {
	server := &fakeRasterizerServer{plan: []stepResult{errStep(status.Error(codes.InvalidArgument, "bad request"))}}
	client := newTestClient(t, server, time.Second)

	_, err := client.Render(context.Background(), &rasterproto.RenderGlyphRequest{})
	if status.Code(err) != codes.InvalidArgument {
		t.Fatalf("err = %v, want InvalidArgument", err)
	}
	if server.callCount() != 1 {
		t.Fatalf("calls = %d, want 1 (no retry)", server.callCount())
	}
}

func TestRenderExhaustsRetries(t *testing.T) {
	server := &fakeRasterizerServer{plan: []stepResult{
		errStep(status.Error(codes.Unavailable, "down")),
		errStep(status.Error(codes.Unavailable, "down")),
		errStep(status.Error(codes.Unavailable, "down")),
	}}
	client := newTestClient(t, server, time.Second)

	_, err := client.Render(context.Background(), &rasterproto.RenderGlyphRequest{})
	if status.Code(err) != codes.Unavailable {
		t.Fatalf("err = %v, want Unavailable", err)
	}
	if server.callCount() != maxAttempts {
		t.Fatalf("calls = %d, want %d", server.callCount(), maxAttempts)
	}
}

func TestRenderHonorsDeadlineWithoutRetry(t *testing.T) {
	server := &fakeRasterizerServer{sleep: 500 * time.Millisecond}
	client := newTestClient(t, server, 100*time.Millisecond)

	_, err := client.Render(context.Background(), &rasterproto.RenderGlyphRequest{})
	if status.Code(err) != codes.DeadlineExceeded {
		t.Fatalf("err = %v, want DeadlineExceeded", err)
	}
	if server.callCount() != 1 {
		t.Fatalf("calls = %d, want 1 (deadline is not retried)", server.callCount())
	}
}

func TestRenderWithCancelledContextFailsFast(t *testing.T) {
	server := &fakeRasterizerServer{}
	client := newTestClient(t, server, time.Second)
	ctx, cancel := context.WithCancel(context.Background())
	cancel()

	_, err := client.Render(ctx, &rasterproto.RenderGlyphRequest{})
	if err == nil {
		t.Fatal("Render succeeded with cancelled context")
	}
}

func TestRenderRetriesResourceExhausted(t *testing.T) {
	server := &fakeRasterizerServer{plan: []stepResult{
		errStep(status.Error(codes.ResourceExhausted, "throttled")),
		okStep(&rasterproto.RenderGlyphResponse{ObjectKey: "throttled-then-ok.png"}),
	}}
	client := newTestClient(t, server, time.Second)

	response, err := client.Render(context.Background(), &rasterproto.RenderGlyphRequest{})
	if err != nil {
		t.Fatalf("Render: %v", err)
	}
	if response.ObjectKey != "throttled-then-ok.png" {
		t.Fatalf("response = %+v", response)
	}
	if server.callCount() != 2 {
		t.Fatalf("calls = %d, want 2", server.callCount())
	}
}

func TestNewCreatesClient(t *testing.T) {
	client, err := New("127.0.0.1:1")
	if err != nil {
		t.Fatalf("New: %v", err)
	}
	t.Cleanup(func() { _ = client.Close() })
	if client.Deadline != DefaultDeadline {
		t.Fatalf("Deadline = %v, want %v", client.Deadline, DefaultDeadline)
	}
}

func TestCloseIsIdempotent(t *testing.T) {
	server := &fakeRasterizerServer{}
	client := newTestClient(t, server, time.Second)
	if err := client.Close(); err != nil {
		t.Fatalf("Close: %v", err)
	}
}

func TestIsTransientRejectsPlainErrors(t *testing.T) {
	if isTransient(context.DeadlineExceeded) {
		t.Fatal("plain error reported transient")
	}
}

func TestRenderReturnsCtxErrorDuringBackoff(t *testing.T) {
	server := &fakeRasterizerServer{plan: []stepResult{
		errStep(status.Error(codes.Unavailable, "down")),
		errStep(status.Error(codes.Unavailable, "down")),
	}}
	client := newTestClient(t, server, time.Second)
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Millisecond)
	defer cancel()

	_, err := client.Render(ctx, &rasterproto.RenderGlyphRequest{})
	if err == nil {
		t.Fatal("Render succeeded, want context error")
	}
	if server.callCount() != 1 {
		t.Fatalf("calls = %d, want 1 (context expired during backoff)", server.callCount())
	}
}

func TestRenderDefaultsDeadlineWhenUnset(t *testing.T) {
	server := &fakeRasterizerServer{plan: []stepResult{okStep(&rasterproto.RenderGlyphResponse{ObjectKey: "default-deadline.png"})}}
	client := newTestClient(t, server, 0)
	client.Deadline = 0

	response, err := client.Render(context.Background(), &rasterproto.RenderGlyphRequest{})
	if err != nil {
		t.Fatalf("Render: %v", err)
	}
	if response.ObjectKey != "default-deadline.png" {
		t.Fatalf("response = %+v", response)
	}
}
