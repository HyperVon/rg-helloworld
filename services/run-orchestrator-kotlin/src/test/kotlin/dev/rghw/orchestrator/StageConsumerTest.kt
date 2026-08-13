package dev.rghw.orchestrator

import org.apache.kafka.clients.consumer.ConsumerRecord
import org.apache.kafka.clients.consumer.MockConsumer
import org.apache.kafka.clients.consumer.OffsetResetStrategy
import org.apache.kafka.common.TopicPartition
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

class StageConsumerTest {
    @Test
    fun pollOnceDispatchesRecordsToTheMonitor() {
        val consumer = MockConsumer<String, String>(OffsetResetStrategy.EARLIEST)
        consumer.subscribe(
            listOf(
                Services.GEOMETRY_TOPIC,
                Services.NORMALIZED_TOPIC,
                Services.RASTERIZED_TOPIC,
                Services.PHRASE_COMPOSED_TOPIC,
                Services.OCR_IMAGES_TOPIC,
                Services.OCR_OBSERVATIONS_TOPIC,
                Services.SYMBOLS_ADJUDICATED_TOPIC,
                Services.QUALITY_RETRY_TOPIC,
                Services.PHRASE_ASSEMBLED_TOPIC,
            ),
        )
        val geometryPartition = TopicPartition(Services.GEOMETRY_TOPIC, 0)
        val normalizedPartition = TopicPartition(Services.NORMALIZED_TOPIC, 0)
        val rasterizedPartition = TopicPartition(Services.RASTERIZED_TOPIC, 0)
        consumer.rebalance(listOf(geometryPartition, normalizedPartition, rasterizedPartition))
        consumer.updateBeginningOffsets(mapOf(geometryPartition to 0L, normalizedPartition to 0L, rasterizedPartition to 0L))

        val rawGeometry = stageEvent(Services.GEOMETRY_TOPIC, "r1", "g0", 10, 20)
        val rawNormalized = stageEvent(Services.NORMALIZED_TOPIC, "r1", "g0", 20, 30)
        val rawRasterized = stageEvent(Services.RASTERIZED_TOPIC, "r1", "g0", 30, 40)
        consumer.addRecord(ConsumerRecord(Services.GEOMETRY_TOPIC, 0, 0L, "r1:g0", rawGeometry))
        consumer.addRecord(ConsumerRecord(Services.NORMALIZED_TOPIC, 0, 1L, "r1:g0", rawNormalized))
        consumer.addRecord(ConsumerRecord(Services.RASTERIZED_TOPIC, 0, 2L, "r1:g0", rawRasterized))

        val tracker = StageProgressTracker()
        tracker.registerRun("r1", 1, drawableCount = 1)
        val monitor = StageMonitor(tracker, StageEventValidator())
        val stageConsumer = StageConsumer(consumer, monitor, pollTimeoutMs = 10)

        val count = stageConsumer.pollOnce()

        assertEquals(3, count)
        assertEquals(
            StageTransition.STAGE_COMPLETE,
            tracker.onGeometryEvent("r1", "g0"),
            "geometry record must reach the tracker",
        )
        assertEquals(
            StageTransition.STAGE_COMPLETE,
            tracker.onNormalizedEvent("r1", "g0"),
            "normalized record must reach the tracker",
        )
        assertEquals(
            StageTransition.STAGE_COMPLETE,
            tracker.onRasterizedEvent("r1", "g0"),
            "rasterized record must reach the tracker",
        )
        consumer.close()
    }

    @Test
    fun pollOnceReturnsZeroWhenNoRecords() {
        val consumer = MockConsumer<String, String>(OffsetResetStrategy.EARLIEST)
        consumer.subscribe(listOf(Services.GEOMETRY_TOPIC))
        val partition = TopicPartition(Services.GEOMETRY_TOPIC, 0)
        consumer.rebalance(listOf(partition))
        consumer.updateBeginningOffsets(mapOf(partition to 0L))

        val stageConsumer = StageConsumer(consumer, StageMonitor(StageProgressTracker(), StageEventValidator()))
        assertEquals(0, stageConsumer.pollOnce())
        consumer.close()
    }

    @Test
    fun runForeverStopsAfterMaxPolls() {
        val consumer = MockConsumer<String, String>(OffsetResetStrategy.EARLIEST)
        consumer.subscribe(listOf(Services.GEOMETRY_TOPIC))
        val partition = TopicPartition(Services.GEOMETRY_TOPIC, 0)
        consumer.rebalance(listOf(partition))
        consumer.updateBeginningOffsets(mapOf(partition to 0L))

        val stageConsumer = StageConsumer(consumer, StageMonitor(StageProgressTracker(), StageEventValidator()))
        stageConsumer.runForever(maxPolls = 2)
        consumer.close()
    }

    @Test
    fun bootstrapConstructorCanCloseWithoutPolling() {
        val stageConsumer =
            StageConsumer(
                "localhost:9092",
                StageMonitor(StageProgressTracker(), StageEventValidator()),
            )

        stageConsumer.runForever(maxPolls = 0)
    }
}
