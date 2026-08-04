# ADR-0002: Apache Kafka in KRaft mode

- Status: Accepted
- Date: 2026-08-04

## Context

The architecture requires durable, ordered, replayable domain events between
services, and explicitly forbids replacing Kafka with Redis (or vice versa).
Apache Kafka traditionally required ZooKeeper.

## Decision

Run a single-node **Apache Kafka 4.x broker in KRaft mode** inside Kubernetes:
one replica, one partition per topic, short local retention, persistent volume,
no ZooKeeper, no external connections. Topics and partitioning follow
architecture section 13.

## Consequences

- No ZooKeeper dependency; simpler local operation.
- KRaft is the supported path forward for Apache Kafka.
- Single-broker topology is a deliberate trade-off for laptop operation;
  ordering guarantees for glyph-level events rely on partition keys
  (`runId:glyphInstanceId`).
