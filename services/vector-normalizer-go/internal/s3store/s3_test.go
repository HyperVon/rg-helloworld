package s3store

import (
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

const locationXML = `<?xml version="1.0" encoding="UTF-8"?><LocationConstraint xmlns="http://s3.amazonaws.com/doc/2006-03-01/"></LocationConstraint>`

// minioServer emulates the minimal MinIO surface minio-go exercises:
// the GetBucketLocation probe, PUT, and GET object calls.
func minioServer(t *testing.T, putStatus int, onPut func(r *http.Request, body string)) *httptest.Server {
	t.Helper()
	return httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case r.Method == http.MethodGet && strings.HasSuffix(r.URL.Path, "/") &&
			func() bool { _, ok := r.URL.Query()["location"]; return ok }():
			w.Header().Set("Content-Type", "application/xml")
			_, _ = w.Write([]byte(locationXML))
		case r.Method == http.MethodPut:
			body, _ := io.ReadAll(r.Body)
			if onPut != nil {
				onPut(r, string(body))
			}
			w.Header().Set("ETag", `"fake-etag"`)
			w.WriteHeader(putStatus)
		case r.Method == http.MethodGet:
			w.Header().Set("Last-Modified", "Mon, 02 Jan 2006 15:04:05 GMT")
			w.Header().Set("Content-Length", "15")
			_, _ = w.Write([]byte(`{"stored":true}`))
		default:
			w.WriteHeader(http.StatusOK)
		}
	}))
}

func TestPutObjectRoundTrip(t *testing.T) {
	var seenPath, seenBody, seenType string
	var puts int
	server := minioServer(t, http.StatusOK, func(r *http.Request, body string) {
		puts++
		seenPath = r.URL.Path
		seenType = r.Header.Get("Content-Type")
		seenBody = body
	})
	defer server.Close()

	endpoint := strings.TrimPrefix(server.URL, "http://")
	store, err := New(endpoint, "minioadmin", "minioadmin", false)
	if err != nil {
		t.Fatalf("New: %v", err)
	}
	body := []byte(`{"kind":"DRAWABLE_GEOMETRY"}`)
	if err := store.PutObject(context.Background(), "rube-goldberg-artifacts",
		"runs/run-1/glyphs/0-gid/normalized-attempt-1-a.json", body, "application/json"); err != nil {
		t.Fatalf("PutObject: %v", err)
	}
	if puts != 1 {
		t.Fatalf("PUT count = %d, want 1", puts)
	}
	if seenPath != "/rube-goldberg-artifacts/runs/run-1/glyphs/0-gid/normalized-attempt-1-a.json" {
		t.Fatalf("path = %q", seenPath)
	}
	// minio-go streams the body with AWS chunked signing; the payload must
	// appear verbatim inside the stream.
	if !strings.Contains(seenBody, string(body)) {
		t.Fatalf("body = %q, want it to contain %q", seenBody, body)
	}
	if seenType != "application/json" {
		t.Fatalf("content type = %q", seenType)
	}
}

func TestPutObjectServerError(t *testing.T) {
	server := minioServer(t, http.StatusInternalServerError, nil)
	defer server.Close()

	store, err := New(strings.TrimPrefix(server.URL, "http://"), "minioadmin", "minioadmin", false)
	if err != nil {
		t.Fatalf("New: %v", err)
	}
	if err := store.PutObject(context.Background(), "bucket", "key", []byte("{}"), "application/json"); err == nil {
		t.Fatal("PutObject succeeded, want error on 500")
	}
}

func TestReadObject(t *testing.T) {
	server := minioServer(t, http.StatusOK, nil)
	defer server.Close()

	store, err := New(strings.TrimPrefix(server.URL, "http://"), "minioadmin", "minioadmin", false)
	if err != nil {
		t.Fatalf("New: %v", err)
	}
	body, err := store.ReadObject(context.Background(), "bucket", "key")
	if err != nil {
		t.Fatalf("ReadObject: %v", err)
	}
	if string(body) != `{"stored":true}` {
		t.Fatalf("body = %q", body)
	}
}

func TestReadObjectServerError(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodGet && strings.HasSuffix(r.URL.Path, "/") &&
			func() bool { _, ok := r.URL.Query()["location"]; return ok }() {
			w.Header().Set("Content-Type", "application/xml")
			_, _ = w.Write([]byte(locationXML))
			return
		}
		w.WriteHeader(http.StatusNotFound)
	}))
	defer server.Close()

	store, err := New(strings.TrimPrefix(server.URL, "http://"), "minioadmin", "minioadmin", false)
	if err != nil {
		t.Fatalf("New: %v", err)
	}
	if _, err := store.ReadObject(context.Background(), "bucket", "missing"); err == nil {
		t.Fatal("ReadObject succeeded, want error on 404")
	}
}

func TestNewRejectsBadEndpoint(t *testing.T) {
	if _, err := New("not a host", "a", "b", false); err == nil {
		t.Fatal("New with invalid endpoint should fail")
	}
}
