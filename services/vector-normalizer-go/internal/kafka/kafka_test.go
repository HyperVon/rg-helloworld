package kafka

import (
	"context"
	"testing"
	"time"

	"github.com/twmb/franz-go/pkg/kadm"
	"github.com/twmb/franz-go/pkg/kfake"
	"github.com/twmb/franz-go/pkg/kgo"
)

const testTopic = "rg.geometry-expanded.v1"

func TestPollAndProduceAgainstKfake(t *testing.T) {
	cluster, err := kfake.NewCluster(kfake.NumBrokers(1))
	if err != nil {
		t.Fatalf("kfake cluster: %v", err)
	}
	defer cluster.Close()

	// Seed client attached to the cluster; it creates topics and produces.
	seed, err := kgo.NewClient(kgo.SeedBrokers(cluster.ListenAddrs()...),
		kgo.ConsumeTopics("rg.glyph-normalized.v1"))
	if err != nil {
		t.Fatalf("seed client: %v", err)
	}
	defer seed.Close()
	admin := kadm.NewClient(seed)
	create := func(topic string) {
		response, err := admin.CreateTopics(context.Background(), 1, 1, nil, topic)
		if err != nil || response[topic].Err != nil {
			t.Fatalf("create topic %s: %v %v", topic, err, response[topic].Err)
		}
	}
	create(testTopic)
	create("rg.glyph-normalized.v1")

	produce := func(topic, key, value string) {
		record := &kgo.Record{Topic: topic, Key: []byte(key), Value: []byte(value)}
		if err := seed.ProduceSync(context.Background(), record).FirstErr(); err != nil {
			t.Fatalf("seed produce: %v", err)
		}
	}
	produce(testTopic, "run-1:glyph-1", `{"hello":"world"}`)
	produce(testTopic, "run-1:glyph-2", `{"second":true}`)

	transport, err := New(cluster.ListenAddrs()[0], "test-group", testTopic)
	if err != nil {
		t.Fatalf("New: %v", err)
	}
	defer transport.Close()

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	first, ok := transport.Poll(ctx)
	if !ok {
		t.Fatal("poll returned no message")
	}
	if first != `{"hello":"world"}` {
		t.Fatalf("first message = %q", first)
	}
	second, ok := transport.Poll(ctx)
	if !ok {
		t.Fatal("poll returned no second message")
	}
	if second != `{"second":true}` {
		t.Fatalf("second message = %q", second)
	}

	// Manual commit persists the consumed offsets.
	if err := transport.Commit(ctx); err != nil {
		t.Fatalf("Commit: %v", err)
	}

	// Produce a reply on the second topic and read it back with the seed
	// client (which consumes that topic).
	if err := transport.Produce(ctx, "rg.glyph-normalized.v1", "run-1:glyph-1",
		`{"normalized":true}`); err != nil {
		t.Fatalf("Produce: %v", err)
	}
	reply := seed.PollFetches(ctx).Records()
	if len(reply) == 0 || string(reply[0].Value) != `{"normalized":true}` {
		t.Fatalf("reply = %+v", reply)
	}
	if reply[0].Topic != "rg.glyph-normalized.v1" || string(reply[0].Key) != "run-1:glyph-1" {
		t.Fatalf("reply metadata wrong: %+v", reply[0])
	}
}

func TestNewIsLazy(t *testing.T) {
	// kgo clients connect lazily; New must not fail on an unreachable
	// broker at construction time.
	transport, err := New("127.0.0.1:1", "g", testTopic)
	if err != nil {
		t.Fatalf("New with unreachable broker failed: %v", err)
	}
	transport.Close()
}

func TestProduceAfterCloseFails(t *testing.T) {
	cluster, err := kfake.NewCluster(kfake.NumBrokers(1))
	if err != nil {
		t.Fatalf("kfake cluster: %v", err)
	}
	defer cluster.Close()
	transport, err := New(cluster.ListenAddrs()[0], "closed-group", testTopic)
	if err != nil {
		t.Fatalf("New: %v", err)
	}
	transport.Close()
	if err := transport.Produce(context.Background(), "rg.glyph-normalized.v1", "k", "v"); err == nil {
		t.Fatal("Produce after Close succeeded, want error")
	}
}

func TestPollTimeoutReturnsFalse(t *testing.T) {
	cluster, err := kfake.NewCluster(kfake.NumBrokers(1))
	if err != nil {
		t.Fatalf("kfake cluster: %v", err)
	}
	defer cluster.Close()
	// The transport subscribes to an empty topic; the poll must time out.
	transport, err := New(cluster.ListenAddrs()[0], "timeout-group", "rg.glyph-normalized.v1")
	if err != nil {
		t.Fatalf("New: %v", err)
	}
	defer transport.Close()
	ctx, cancel := context.WithTimeout(context.Background(), 500*time.Millisecond)
	defer cancel()
	if _, ok := transport.Poll(ctx); ok {
		t.Fatal("poll on empty topic returned a message")
	}
	if ctx.Err() == nil {
		t.Fatal("context deadline not reached")
	}
}
