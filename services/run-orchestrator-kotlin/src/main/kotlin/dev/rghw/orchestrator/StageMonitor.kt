package dev.rghw.orchestrator

import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.apache.kafka.clients.consumer.Consumer
import org.apache.kafka.clients.consumer.ConsumerRecord
import org.apache.kafka.clients.consumer.KafkaConsumer
import java.time.Duration
import java.util.Properties
import java.util.concurrent.ConcurrentHashMap

// Stage monitoring for Milestone 6/7: the orchestrator consumes
// GeometryExpanded, VectorNormalized, GlyphRasterized, PhraseComposed, and
// OcrImagePrepared events, validates them (maturity must strictly increase;
// section 7.4 prohibited fields are rejected), and fans the per-glyph
// completions in to drive the run state machine
// PLANNING -> GENERATING_GEOMETRY -> NORMALIZING -> RASTERIZING ->
// COMPOSING -> PREPROCESSING -> OCR_RUNNING -> ADJUDICATING ->
// ASSEMBLING -> VALIDATING -> SUCCEEDED. Gap positions have layout
// metadata but no raster, so the rasterized fan-in counts only drawable
// glyphs. Composition and preprocessing are run-level fan-ins (one event
// each per run).

data class MaturityPair(
    val input: Int,
    val output: Int,
)

sealed class ValidationResult {
    object Valid : ValidationResult()

    data class Rejected(
        val reason: String,
    ) : ValidationResult()
}

class StageEventValidator {
    private val prohibitedFields =
        setOf("message", "targetText", "expectedCharacter", "unicodeCodePoint", "characterName", "glyphLabel")
    private val prohibitedPattern = Regex("\"(message|targetText|expectedCharacter|unicodeCodePoint|characterName|glyphLabel)\"\\s*:")

    fun validate(
        rawEvent: String,
        expected: MaturityPair,
    ): ValidationResult {
        val prohibited = prohibitedPattern.find(rawEvent)
        if (prohibited != null) {
            return ValidationResult.Rejected("prohibited field present in downstream event: ${prohibited.groupValues[1]}")
        }
        val parsed =
            try {
                kotlinx.serialization.json.Json
                    .parseToJsonElement(rawEvent)
                    .jsonObject
            } catch (e: Exception) {
                return ValidationResult.Rejected("malformed event JSON: ${e.message}")
            }
        val data = parsed["data"]?.jsonObject ?: return ValidationResult.Rejected("event has no data object")
        val inputMaturity =
            data["inputMaturity"]?.jsonPrimitive?.intOrNull ?: return ValidationResult.Rejected("event has no inputMaturity")
        val outputMaturity =
            data["outputMaturity"]?.jsonPrimitive?.intOrNull ?: return ValidationResult.Rejected("event has no outputMaturity")
        if (outputMaturity <= inputMaturity) {
            return ValidationResult.Rejected(
                "maturity regression: $inputMaturity -> $outputMaturity (rank must strictly increase)",
            )
        }
        if (inputMaturity != expected.input || outputMaturity != expected.output) {
            return ValidationResult.Rejected(
                "maturity mismatch: $inputMaturity -> $outputMaturity (expected ${expected.input} -> ${expected.output})",
            )
        }
        return ValidationResult.Valid
    }
}

enum class StageTransition {
    PROGRESS,
    STAGE_COMPLETE,
    RUN_COMPLETE,
    UNKNOWN_RUN,
}

class StageProgressTracker {
    private val expectedTotals = ConcurrentHashMap<String, Int>()
    private val drawableTotals = ConcurrentHashMap<String, Int>()
    private val geometryCompleted = ConcurrentHashMap<String, MutableSet<String>>()
    private val normalizedCompleted = ConcurrentHashMap<String, MutableSet<String>>()
    private val rasterizedCompleted = ConcurrentHashMap<String, MutableSet<String>>()
    private val compositionCompleted = ConcurrentHashMap.newKeySet<String>()
    private val ocrPreparedCompleted = ConcurrentHashMap.newKeySet<String>()
    private val ocrObservationsReceived = ConcurrentHashMap.newKeySet<String>()
    private val symbolsAdjudicatedCompleted = ConcurrentHashMap.newKeySet<String>()

    fun registerRun(
        runId: String,
        glyphCount: Int,
        drawableCount: Int = glyphCount,
    ) {
        expectedTotals[runId] = glyphCount
        drawableTotals[runId] = drawableCount
        geometryCompleted[runId] = ConcurrentHashMap.newKeySet()
        normalizedCompleted[runId] = ConcurrentHashMap.newKeySet()
        rasterizedCompleted[runId] = ConcurrentHashMap.newKeySet()
    }

    fun onGeometryEvent(
        runId: String,
        glyphInstanceId: String,
    ): StageTransition {
        val total = expectedTotals[runId] ?: return StageTransition.UNKNOWN_RUN
        val completed = geometryCompleted.getOrPut(runId) { ConcurrentHashMap.newKeySet() }
        completed.add(glyphInstanceId)
        return if (completed.size >= total) StageTransition.STAGE_COMPLETE else StageTransition.PROGRESS
    }

    fun onNormalizedEvent(
        runId: String,
        glyphInstanceId: String,
    ): StageTransition {
        val total = expectedTotals[runId] ?: return StageTransition.UNKNOWN_RUN
        val completed = normalizedCompleted.getOrPut(runId) { ConcurrentHashMap.newKeySet() }
        completed.add(glyphInstanceId)
        return if (completed.size >= total) StageTransition.STAGE_COMPLETE else StageTransition.PROGRESS
    }

    fun onRasterizedEvent(
        runId: String,
        glyphInstanceId: String,
    ): StageTransition {
        val total = drawableTotals[runId] ?: return StageTransition.UNKNOWN_RUN
        val completed = rasterizedCompleted.getOrPut(runId) { ConcurrentHashMap.newKeySet() }
        completed.add(glyphInstanceId)
        return if (completed.size >= total) StageTransition.STAGE_COMPLETE else StageTransition.PROGRESS
    }

    fun markComposed(runId: String): StageTransition {
        if (!expectedTotals.containsKey(runId)) return StageTransition.UNKNOWN_RUN
        compositionCompleted.add(runId)
        return StageTransition.STAGE_COMPLETE
    }

    fun markOcrPrepared(runId: String): StageTransition {
        if (!expectedTotals.containsKey(runId)) return StageTransition.UNKNOWN_RUN
        ocrPreparedCompleted.add(runId)
        return StageTransition.STAGE_COMPLETE
    }

    fun markOcrObservationsReceived(runId: String): StageTransition {
        if (!expectedTotals.containsKey(runId)) return StageTransition.UNKNOWN_RUN
        ocrObservationsReceived.add(runId)
        return StageTransition.STAGE_COMPLETE
    }

    fun markSymbolsAdjudicated(runId: String): StageTransition {
        if (!expectedTotals.containsKey(runId)) return StageTransition.UNKNOWN_RUN
        symbolsAdjudicatedCompleted.add(runId)
        return StageTransition.STAGE_COMPLETE
    }
}

class StageMonitor(
    private val tracker: StageProgressTracker,
    private val validator: StageEventValidator,
) {
    fun registerRun(
        runId: String,
        glyphCount: Int,
        drawableCount: Int = glyphCount,
    ) {
        tracker.registerRun(runId, glyphCount, drawableCount)
    }

    fun handle(
        topic: String,
        rawEvent: String,
    ) {
        val expected =
            when (topic) {
                Services.GEOMETRY_TOPIC -> MaturityPair(10, 20)
                Services.NORMALIZED_TOPIC -> MaturityPair(20, 30)
                Services.RASTERIZED_TOPIC -> MaturityPair(30, 40)
                Services.PHRASE_COMPOSED_TOPIC -> MaturityPair(40, 50)
                Services.OCR_IMAGES_TOPIC -> MaturityPair(50, 60)
                Services.OCR_OBSERVATIONS_TOPIC -> MaturityPair(60, 70)
                Services.SYMBOLS_ADJUDICATED_TOPIC -> MaturityPair(70, 80)
                Services.PHRASE_ASSEMBLED_TOPIC -> MaturityPair(80, 90)
                else -> return
            }
        val parsed =
            try {
                kotlinx.serialization.json.Json
                    .parseToJsonElement(rawEvent)
                    .jsonObject
            } catch (e: Exception) {
                return
            }
        val runId =
            parsed["correlationid"]?.jsonPrimitive?.contentOrNull
                ?: parsed["data"]
                    ?.jsonObject
                    ?.get("runId")
                    ?.jsonPrimitive
                    ?.contentOrNull
                ?: return
        if (runs[runId] == null) {
            return
        }

        when (val result = validator.validate(rawEvent, expected)) {
            is ValidationResult.Rejected -> {
                System.err.println("stage event rejected for run $runId: ${result.reason}")
                failRun(runId, "stage event rejected: ${result.reason}")
            }

            ValidationResult.Valid -> {
                val data = parsed["data"]?.jsonObject ?: return
                when (topic) {
                    Services.GEOMETRY_TOPIC -> {
                        val glyphInstanceId = data["glyphInstanceId"]?.jsonPrimitive?.contentOrNull ?: return
                        if (tracker.onGeometryEvent(runId, glyphInstanceId) == StageTransition.STAGE_COMPLETE) {
                            transitionRun(runId, RunEvent.GEOMETRY_COMPLETE)
                        }
                    }

                    Services.NORMALIZED_TOPIC -> {
                        val glyphInstanceId = data["glyphInstanceId"]?.jsonPrimitive?.contentOrNull ?: return
                        if (tracker.onNormalizedEvent(runId, glyphInstanceId) == StageTransition.STAGE_COMPLETE) {
                            transitionRun(runId, RunEvent.NORMALIZED_COMPLETE)
                        }
                    }

                    Services.RASTERIZED_TOPIC -> {
                        val glyphInstanceId = data["glyphInstanceId"]?.jsonPrimitive?.contentOrNull ?: return
                        if (tracker.onRasterizedEvent(runId, glyphInstanceId) == StageTransition.STAGE_COMPLETE) {
                            transitionRun(runId, RunEvent.RASTERIZED_COMPLETE)
                        }
                    }

                    Services.PHRASE_COMPOSED_TOPIC -> {
                        if (tracker.markComposed(runId) == StageTransition.STAGE_COMPLETE) {
                            transitionRun(runId, RunEvent.COMPOSED_COMPLETE)
                        }
                    }

                    Services.OCR_IMAGES_TOPIC -> {
                        if (tracker.markOcrPrepared(runId) == StageTransition.STAGE_COMPLETE) {
                            transitionRun(runId, RunEvent.PREPROCESSED_COMPLETE)
                        }
                    }

                    Services.OCR_OBSERVATIONS_TOPIC -> {
                        if (tracker.markOcrObservationsReceived(runId) == StageTransition.STAGE_COMPLETE) {
                            transitionRun(runId, RunEvent.OCR_OBSERVATIONS_RECEIVED)
                        }
                    }

                    Services.SYMBOLS_ADJUDICATED_TOPIC -> {
                        val glyphInstanceId = data["glyphInstanceId"]?.jsonPrimitive?.contentOrNull ?: return
                        if (tracker.markSymbolsAdjudicated(runId) == StageTransition.STAGE_COMPLETE) {
                            transitionRun(runId, RunEvent.ADJUDICATED_COMPLETE)
                        }
                    }

                    Services.QUALITY_RETRY_TOPIC -> {
                        val reason = data["reason"]?.jsonPrimitive?.contentOrNull ?: "unknown"
                        System.err.println("quality retry requested for run $runId: $reason")
                    }

                    Services.PHRASE_ASSEMBLED_TOPIC -> {
                        val assembledText = data["assembledText"]?.jsonPrimitive?.contentOrNull
                        handleAssembly(runId, assembledText)
                    }
                }
            }
        }
    }

    private fun handleAssembly(
        runId: String,
        assembledText: String?,
    ) {
        if (assembledText == null) {
            failRun(runId, "assembly event missing assembledText")
            return
        }
        val expected = expectedTexts[runId]
        if (expected == null) {
            failRun(runId, "assembly event received but no expected text stored for run")
            return
        }
        if (assembledText != expected) {
            failRun(runId, "output mismatch: assembled text does not match expected phrase")
            return
        }
        completeRun(runId, assembledText)
    }
}

class StageConsumer(
    private val bootstrap: String,
    private val monitor: StageMonitor,
    private val pollTimeoutMs: Long = 500,
) {
    private val topics =
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
        )

    private var consumer: Consumer<String, String>? = null

    init {
        if (bootstrap.isNotEmpty()) {
            consumer = createConsumer()
        }
    }

    constructor(
        consumer: Consumer<String, String>,
        monitor: StageMonitor,
        pollTimeoutMs: Long = 500,
    ) : this("", monitor, pollTimeoutMs) {
        this.consumer = consumer
    }

    private fun createConsumer(): Consumer<String, String> =
        KafkaConsumer<String, String>(consumerProperties(bootstrap)).also { it.subscribe(topics) }

    private fun recreateConsumer() {
        try {
            consumer!!.close()
        } catch (e: Exception) {
            System.err.println("stage consumer close error: ${e.message}")
        }
        consumer = createConsumer()
    }

    fun pollOnce(): Int {
        val records = consumer!!.poll(Duration.ofMillis(pollTimeoutMs))
        var count = 0
        for (record: ConsumerRecord<String, String> in records) {
            monitor.handle(record.topic(), record.value())
            count++
        }
        return count
    }

    fun runForever(maxPolls: Int = Int.MAX_VALUE) {
        var polls = 0
        while (polls < maxPolls) {
            try {
                pollOnce()
                polls++
            } catch (e: Exception) {
                System.err.println("stage consumer poll error: ${e.message}")
                recreateConsumer()
            }
        }
        consumer!!.close()
    }
}
