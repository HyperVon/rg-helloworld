// Package kafka wraps franz-go for consume-process-produce loops.
package kafka

import (
	"context"
	"fmt"
	"time"

	"github.com/twmb/franz-go/pkg/kgo"
)

// Transport is the Kafka boundary used by the worker.
type Transport interface {
	Poll(ctx context.Context) (message string, ok bool)
	Produce(ctx context.Context, topic, key, value string) error
	Commit(ctx context.Context) error
	Close()
}

// KafkaTransport is a franz-go-backed transport with manual offset commits.
type KafkaTransport struct {
	client  *kgo.Client
	pending []string
}

// New creates a consumer-group client for the given topics.
func New(bootstrap, groupID string, topics ...string) (*KafkaTransport, error) {
	client, err := kgo.NewClient(
		kgo.SeedBrokers(bootstrap),
		kgo.ConsumerGroup(groupID),
		kgo.ConsumeTopics(topics...),
		kgo.DisableAutoCommit(),
		kgo.FetchMaxWait(500*time.Millisecond),
	)
	if err != nil {
		return nil, fmt.Errorf("kafka client: %w", err)
	}
	return &KafkaTransport{client: client}, nil
}

// Poll blocks until a record is available or the context ends. Records from
// one fetch are buffered and returned one at a time so none are lost.
func (k *KafkaTransport) Poll(ctx context.Context) (string, bool) {
	if len(k.pending) > 0 {
		message := k.pending[0]
		k.pending = k.pending[1:]
		return message, true
	}
	fetches := k.client.PollFetches(ctx)
	if fetches.IsClientClosed() || len(fetches) == 0 {
		return "", false
	}
	records := fetches.Records()
	if len(records) == 0 {
		return "", false
	}
	for _, record := range records {
		k.pending = append(k.pending, string(record.Value))
	}
	message := k.pending[0]
	k.pending = k.pending[1:]
	return message, true
}

// Produce sends one record and waits for its delivery report.
func (k *KafkaTransport) Produce(ctx context.Context, topic, key, value string) error {
	record := &kgo.Record{Topic: topic, Key: []byte(key), Value: []byte(value)}
	if err := k.client.ProduceSync(ctx, record).FirstErr(); err != nil {
		return fmt.Errorf("kafka produce %s: %w", topic, err)
	}
	return nil
}

// Commit persists the current offsets so redelivery only happens after a
// crash between processing and commit (at-least-once).
func (k *KafkaTransport) Commit(ctx context.Context) error {
	if err := k.client.CommitUncommittedOffsets(ctx); err != nil {
		return fmt.Errorf("kafka commit: %w", err)
	}
	return nil
}

// Close releases the client.
func (k *KafkaTransport) Close() { k.client.Close() }

var _ Transport = (*KafkaTransport)(nil)
