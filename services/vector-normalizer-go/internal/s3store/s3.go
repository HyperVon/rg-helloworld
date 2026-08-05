// Package s3store persists artifacts in MinIO.
package s3store

import (
	"bytes"
	"context"
	"fmt"
	"io"

	"github.com/minio/minio-go/v7"
	"github.com/minio/minio-go/v7/pkg/credentials"
)

// Store is the artifact persistence boundary.
type Store interface {
	PutObject(ctx context.Context, bucket, key string, body []byte, contentType string) error
}

// MinIOStore writes objects to a MinIO bucket with deterministic keys.
type MinIOStore struct {
	client *minio.Client
}

// New connects to MinIO at endpoint (host:port). Credentials come from the
// local deployment's minio-credentials secret.
func New(endpoint, accessKey, secretKey string, useSSL bool) (*MinIOStore, error) {
	client, err := minio.New(endpoint, &minio.Options{
		Creds:  credentials.NewStaticV4(accessKey, secretKey, ""),
		Secure: useSSL,
	})
	if err != nil {
		return nil, fmt.Errorf("minio client: %w", err)
	}
	return &MinIOStore{client: client}, nil
}

// PutObject writes one object, failing if the bucket is missing.
func (m *MinIOStore) PutObject(ctx context.Context, bucket, key string, body []byte, contentType string) error {
	_, err := m.client.PutObject(ctx, bucket, key, bytes.NewReader(body), int64(len(body)),
		minio.PutObjectOptions{ContentType: contentType})
	if err != nil {
		return fmt.Errorf("minio put %s/%s: %w", bucket, key, err)
	}
	return nil
}

// Verify that the concrete type satisfies the interface.
var _ Store = (*MinIOStore)(nil)

// ReadObject downloads one object; used by tests and debugging only.
func (m *MinIOStore) ReadObject(ctx context.Context, bucket, key string) ([]byte, error) {
	object, err := m.client.GetObject(ctx, bucket, key, minio.GetObjectOptions{})
	if err != nil {
		return nil, fmt.Errorf("minio get %s/%s: %w", bucket, key, err)
	}
	defer object.Close()
	body, err := io.ReadAll(object)
	if err != nil {
		return nil, fmt.Errorf("minio read %s/%s: %w", bucket, key, err)
	}
	return body, nil
}
