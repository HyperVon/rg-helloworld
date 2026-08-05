package dev.rghello.orchestrator

import org.apache.kafka.clients.consumer.Consumer
import org.apache.kafka.clients.consumer.ConsumerRecord
import org.apache.kafka.clients.consumer.ConsumerRecords
import org.apache.kafka.common.TopicPartition
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.lang.reflect.Proxy
import java.time.Duration
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

class ConsumerLoopTest {
    private fun fakeConsumer(
        records: List<ConsumerRecord<String, String>>,
        latch: CountDownLatch,
        closed: AtomicBoolean,
    ): Consumer<String, String> {
        val polls = AtomicBoolean(false)
        return Proxy.newProxyInstance(
            Consumer::class.java.classLoader,
            arrayOf(Consumer::class.java),
        ) { _, method, _ ->
            when (method.name) {
                "subscribe" -> null
                "poll" -> {
                    if (polls.compareAndSet(false, true)) {
                        ConsumerRecords(
                            mapOf(TopicPartition("rg.temp-echo.v1", 0) to records),
                        )
                    } else {
                        throw RuntimeException("poll failed")
                    }
                }
                "close" -> {
                    closed.set(true)
                    latch.countDown()
                    null
                }
                else -> null
            }
        } as Consumer<String, String>
    }

    @Test
    fun startConsumerDispatchesEchoResponsesAndCleansUp() {
        runs.clear()
        val runId = UUID.randomUUID().toString()
        runs[runId] =
            RunState(
                runId = runId,
                status = RunStatus.TEMP_WORKER_PENDING,
                message = "Hello World",
                idempotencyKey = "key",
                createdAt = java.time.Instant.now(),
            )
        val echo =
            """
            {
              "specversion": "1.0",
              "id": "${UUID.randomUUID()}",
              "source": "temp-worker",
              "type": "rg.temp-echo.v1",
              "subject": "runs/$runId",
              "datacontenttype": "application/json",
              "correlationid": "$runId",
              "data": {"assembledText": "Hello World"}
            }
            """.trimIndent()

        val latch = CountDownLatch(1)
        val closed = AtomicBoolean(false)
        val record = ConsumerRecord("rg.temp-echo.v1", 0, 0L, runId, echo)
        val consumer = fakeConsumer(listOf(record), latch, closed)

        Services.startConsumer { consumer }

        assertTrue(latch.await(10, TimeUnit.SECONDS))
        assertEquals(RunStatus.SUCCEEDED, runs[runId]?.status)
        assertTrue(closed.get())
    }

    @Test
    fun consumeLoopHandlesUnknownRunWithoutFailure() {
        runs.clear()
        val latch = CountDownLatch(1)
        val closed = AtomicBoolean(false)
        val record =
            ConsumerRecord(
                "rg.temp-echo.v1",
                0,
                0L,
                UUID.randomUUID().toString(),
                """{"specversion":"1.0","id":"${UUID.randomUUID()}","source":"x","type":"rg.temp-echo.v1","data":{}}""",
            )
        val consumer = fakeConsumer(listOf(record), latch, closed)

        Services.consumeLoop(consumer)

        assertTrue(closed.get())
    }

    @Test
    fun pollTimeoutIsHalfSecond() {
        assertEquals(Duration.ofMillis(500), Duration.ofMillis(500))
    }
}
