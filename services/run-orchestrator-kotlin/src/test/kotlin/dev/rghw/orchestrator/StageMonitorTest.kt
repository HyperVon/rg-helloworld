package dev.rghw.orchestrator

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertInstanceOf
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import java.util.UUID

fun stageEvent(
    topic: String,
    runId: String,
    glyphInstanceId: String,
    inputMaturity: Int,
    outputMaturity: Int,
    extra: String = "",
): String =
    """
    {
      "specversion": "1.0",
      "id": "${UUID.randomUUID()}",
      "source": "worker",
      "type": "$topic",
      "correlationid": "$runId",
      "datacontenttype": "application/json",
      "data": {
        "runId": "$runId",
        "glyphInstanceId": "$glyphInstanceId",
        "position": 0,
        "attempt": 1,
        "inputMaturity": $inputMaturity,
        "outputMaturity": $outputMaturity,
        "inputArtifacts": [],
        "outputArtifacts": [],
        "transformation": {"name": "expand-geometry", "version": "1.0.0"}
        $extra
      }
    }
    """.trimIndent()

fun assemblyEvent(
    runId: String,
    assembledText: String,
    inputMaturity: Int = 80,
    outputMaturity: Int = 90,
): String =
    """
    {
      "specversion": "1.0",
      "id": "${java.util.UUID.randomUUID()}",
      "source": "phrase-assembler",
      "type": "${Services.PHRASE_ASSEMBLED_TOPIC}",
      "correlationid": "$runId",
      "datacontenttype": "application/json",
      "data": {
        "runId": "$runId",
        "stepId": "${java.util.UUID.randomUUID()}",
        "attempt": 1,
        "inputMaturity": $inputMaturity,
        "outputMaturity": $outputMaturity,
        "inputArtifacts": [],
        "outputArtifacts": [],
        "transformation": {"name": "assemble-phrase", "version": "1.0"},
        "assembledText": "$assembledText",
        "sha256": "abc123"
      }
    }
    """.trimIndent()

class StageEventValidatorTest {
    private val validator = StageEventValidator()

    @Test
    fun acceptsCorrectMaturityPairs() {
        assertEquals(
            ValidationResult.Valid,
            validator.validate(stageEvent(Services.GEOMETRY_TOPIC, "r1", "g1", 10, 20), MaturityPair(10, 20)),
        )
        assertEquals(
            ValidationResult.Valid,
            validator.validate(stageEvent(Services.NORMALIZED_TOPIC, "r1", "g1", 20, 30), MaturityPair(20, 30)),
        )
        assertEquals(
            ValidationResult.Valid,
            validator.validate(stageEvent(Services.RASTERIZED_TOPIC, "r1", "g1", 30, 40), MaturityPair(30, 40)),
        )
    }

    @Test
    fun rejectsBackwardAndEqualMaturity() {
        val backward = validator.validate(stageEvent(Services.GEOMETRY_TOPIC, "r1", "g1", 30, 20), MaturityPair(10, 20))
        assertInstanceOf(ValidationResult.Rejected::class.java, backward)
        assertTrue((backward as ValidationResult.Rejected).reason.contains("regression"))

        val equal = validator.validate(stageEvent(Services.GEOMETRY_TOPIC, "r1", "g1", 10, 10), MaturityPair(10, 20))
        assertInstanceOf(ValidationResult.Rejected::class.java, equal)
        assertTrue((equal as ValidationResult.Rejected).reason.contains("regression"))
    }

    @Test
    fun rejectsWrongMaturityPairForTopic() {
        val wrong = validator.validate(stageEvent(Services.GEOMETRY_TOPIC, "r1", "g1", 20, 30), MaturityPair(10, 20))
        assertInstanceOf(ValidationResult.Rejected::class.java, wrong)
        assertTrue((wrong as ValidationResult.Rejected).reason.contains("mismatch"))
    }

    @Test
    fun rejectsProhibitedFields() {
        // Section 7.4: the runtime validator must reject events that carry
        // the expected output in any downstream schema.
        for (field in listOf("message", "targetText", "expectedCharacter", "unicodeCodePoint", "characterName", "glyphLabel")) {
            val raw = stageEvent(Services.GEOMETRY_TOPIC, "r1", "g1", 10, 20, """, "$field": "H" """)
            val result = validator.validate(raw, MaturityPair(10, 20))
            assertInstanceOf(ValidationResult.Rejected::class.java, result, "field $field must be rejected")
            assertTrue((result as ValidationResult.Rejected).reason.contains(field), "reason: ${result.reason}")
        }
    }

    @Test
    fun rejectsMalformedAndIncompleteEvents() {
        assertInstanceOf(
            ValidationResult.Rejected::class.java,
            validator.validate("not json", MaturityPair(10, 20)),
        )
        val missingData = """{"specversion":"1.0"}"""
        assertInstanceOf(
            ValidationResult.Rejected::class.java,
            validator.validate(missingData, MaturityPair(10, 20)),
        )
        val missingMaturity = """{"specversion":"1.0","data":{"glyphInstanceId":"g1"}}"""
        assertInstanceOf(
            ValidationResult.Rejected::class.java,
            validator.validate(missingMaturity, MaturityPair(10, 20)),
        )
    }
}

class StageProgressTrackerTest {
    private val tracker = StageProgressTracker()

    @Test
    fun fanInCountsUniqueGlyphsAndToleratesDuplicates() {
        tracker.registerRun("r1", 11)
        repeat(10) { index ->
            assertEquals(StageTransition.PROGRESS, tracker.onGeometryEvent("r1", "g$index"))
        }
        assertEquals(StageTransition.PROGRESS, tracker.onGeometryEvent("r1", "g0"), "duplicate must not complete the stage")
        assertEquals(StageTransition.STAGE_COMPLETE, tracker.onGeometryEvent("r1", "g10"))
    }

    @Test
    fun normalizedFanInMovesRunToRasterizing() {
        tracker.registerRun("r1", 2)
        assertEquals(StageTransition.PROGRESS, tracker.onNormalizedEvent("r1", "g0"))
        assertEquals(StageTransition.STAGE_COMPLETE, tracker.onNormalizedEvent("r1", "g1"))
    }

    @Test
    fun rasterizedFanInCompletesRunWithDrawableCount() {
        // "Hello World": 11 positions, 10 drawable (position 5 is a gap).
        tracker.registerRun("r1", 11, drawableCount = 10)
        for (index in 0..9) {
            val transition = tracker.onRasterizedEvent("r1", "g$index")
            if (index < 9) {
                assertEquals(StageTransition.PROGRESS, transition)
            } else {
                assertEquals(StageTransition.STAGE_COMPLETE, transition)
            }
        }
        // Events after completion keep reporting STAGE_COMPLETE; the state
        // machine makes the run-level transition a no-op.
        assertEquals(StageTransition.STAGE_COMPLETE, tracker.onRasterizedEvent("r1", "gap"))
    }

    @Test
    fun unknownRunIsIgnored() {
        assertEquals(StageTransition.UNKNOWN_RUN, tracker.onGeometryEvent("ghost", "g0"))
        assertEquals(StageTransition.UNKNOWN_RUN, tracker.onNormalizedEvent("ghost", "g0"))
        assertEquals(StageTransition.UNKNOWN_RUN, tracker.onRasterizedEvent("ghost", "g0"))
    }
}

class StageMonitorTest {
    @BeforeEach
    fun setUp() {
        runs.clear()
        expectedTexts.clear()
        sseClients.clear()
        lastRunEvents.clear()
        Services.runStateStore = null
        Services.eventProducer = null
    }

    private fun monitor(): StageMonitor = StageMonitor(StageProgressTracker(), StageEventValidator())

    @Test
    fun fullPipelineDrivesRunToPreprocessing() {
        val runId = UUID.randomUUID().toString()
        // The run is GENERATING_GEOMETRY after createRun published the
        // blueprints; the stage events drive it from there.
        runs[runId] = RunState(runId, RunStatus.GENERATING_GEOMETRY, "Hello World", "key", java.time.Instant.now())
        expectedTexts[runId] = "Hello World"
        val store = FakeRunStateStore()
        Services.runStateStore = store
        val producer = FakeEventProducer()
        Services.eventProducer = producer
        val stage = monitor()
        // 11 positions, 10 drawable: the run completes on the rasterized
        // fan-in of the drawable glyphs (position 5 is the gap).
        stage.registerRun(runId, 11, drawableCount = 10)

        repeat(10) { index ->
            stage.handle(Services.GEOMETRY_TOPIC, stageEvent(Services.GEOMETRY_TOPIC, runId, "g$index", 10, 20))
        }
        assertEquals(RunStatus.GENERATING_GEOMETRY, runs[runId]?.status, "run stays in geometry until fan-in")

        stage.handle(Services.GEOMETRY_TOPIC, stageEvent(Services.GEOMETRY_TOPIC, runId, "g10", 10, 20))
        assertEquals(RunStatus.NORMALIZING, runs[runId]?.status)
        assertEquals("NORMALIZING", store.status)

        repeat(10) { index ->
            stage.handle(Services.NORMALIZED_TOPIC, stageEvent(Services.NORMALIZED_TOPIC, runId, "g$index", 20, 30))
        }
        assertEquals(RunStatus.NORMALIZING, runs[runId]?.status)

        stage.handle(Services.NORMALIZED_TOPIC, stageEvent(Services.NORMALIZED_TOPIC, runId, "g10", 20, 30))
        assertEquals(RunStatus.RASTERIZING, runs[runId]?.status)
        assertEquals("RASTERIZING", store.status)

        repeat(9) { index ->
            stage.handle(Services.RASTERIZED_TOPIC, stageEvent(Services.RASTERIZED_TOPIC, runId, "g$index", 30, 40))
        }
        assertEquals(RunStatus.RASTERIZING, runs[runId]?.status, "run stays in rasterizing until drawable fan-in")

        stage.handle(Services.RASTERIZED_TOPIC, stageEvent(Services.RASTERIZED_TOPIC, runId, "g9", 30, 40))
        assertEquals(RunStatus.COMPOSING, runs[runId]?.status, "rasterized fan-in transitions to COMPOSING")

        // Composition event (run-level, maturity 40 -> 50)
        stage.handle(Services.PHRASE_COMPOSED_TOPIC, stageEvent(Services.PHRASE_COMPOSED_TOPIC, runId, "g0", 40, 50))
        assertEquals(RunStatus.PREPROCESSING, runs[runId]?.status, "composed transition moves to PREPROCESSING")

        // OCR prepared event (run-level, maturity 50 -> 60)
        stage.handle(Services.OCR_IMAGES_TOPIC, stageEvent(Services.OCR_IMAGES_TOPIC, runId, "g0", 50, 60))
        assertEquals(RunStatus.OCR_RUNNING, runs[runId]?.status, "preprocessed transition moves to OCR_RUNNING")
    }

    @Test
    fun ocrRunCompleteDrivesRunToAdjudicating() {
        val runId = UUID.randomUUID().toString()
        runs[runId] = RunState(runId, RunStatus.OCR_RUNNING, "Hello World", "key", java.time.Instant.now())
        expectedTexts[runId] = "Hello World"
        val stage = monitor()
        stage.registerRun(runId, 11, drawableCount = 10)

        stage.handle(Services.OCR_OBSERVATIONS_TOPIC, stageEvent(Services.OCR_OBSERVATIONS_TOPIC, runId, "g0", 60, 70))
        assertEquals(RunStatus.ADJUDICATING, runs[runId]?.status, "OCR observations transition moves to ADJUDICATING")
    }

    @Test
    fun adjudicatingCompleteDrivesRunToAssembling() {
        val runId = UUID.randomUUID().toString()
        runs[runId] = RunState(runId, RunStatus.ADJUDICATING, "Hello World", "key", java.time.Instant.now())
        expectedTexts[runId] = "Hello World"
        val stage = monitor()
        stage.registerRun(runId, 11, drawableCount = 10)

        val adjudicated = stageEvent(Services.SYMBOLS_ADJUDICATED_TOPIC, runId, "g0", 70, 80)
        stage.handle(Services.SYMBOLS_ADJUDICATED_TOPIC, adjudicated)
        assertEquals(RunStatus.ASSEMBLING, runs[runId]?.status, "adjudicated transition moves to ASSEMBLING")
    }

    @Test
    fun ocrObservationsMaturityViolationFailsTheRun() {
        val runId = UUID.randomUUID().toString()
        runs[runId] = RunState(runId, RunStatus.OCR_RUNNING, "Hello World", "key", java.time.Instant.now())
        val stage = monitor()
        stage.registerRun(runId, 11, drawableCount = 10)

        stage.handle(Services.OCR_OBSERVATIONS_TOPIC, stageEvent(Services.OCR_OBSERVATIONS_TOPIC, runId, "g0", 50, 60))
        assertEquals(RunStatus.FAILED, runs[runId]?.status, "wrong maturity for OCR observations fails the run")
    }

    @Test
    fun rasterizedMaturityViolationFailsTheRun() {
        val runId = UUID.randomUUID().toString()
        runs[runId] = RunState(runId, RunStatus.RASTERIZING, "Hello World", "key", java.time.Instant.now())
        val stage = monitor()
        stage.registerRun(runId, 1, drawableCount = 1)

        stage.handle(
            Services.RASTERIZED_TOPIC,
            stageEvent(Services.RASTERIZED_TOPIC, runId, "g0", 30, 20),
        )
        assertEquals(RunStatus.FAILED, runs[runId]?.status)
    }

    @Test
    fun maturityViolationFailsTheRun() {
        val runId = UUID.randomUUID().toString()
        runs[runId] = RunState(runId, RunStatus.NORMALIZING, "Hello World", "key", java.time.Instant.now())
        val stage = monitor()
        stage.registerRun(runId, 1)

        stage.handle(
            Services.GEOMETRY_TOPIC,
            stageEvent(Services.GEOMETRY_TOPIC, runId, "g0", 30, 20),
        )
        assertEquals(RunStatus.FAILED, runs[runId]?.status)
    }

    @Test
    fun prohibitedFieldEventFailsTheRun() {
        val runId = UUID.randomUUID().toString()
        runs[runId] = RunState(runId, RunStatus.GENERATING_GEOMETRY, "Hello World", "key", java.time.Instant.now())
        val stage = monitor()
        stage.registerRun(runId, 1)

        // The section 7.4 test: a downstream event deliberately carrying
        // the expected character must fail validation and the run.
        val poisoned = stageEvent(Services.GEOMETRY_TOPIC, runId, "g0", 10, 20, """, "expectedCharacter": "H" """)
        stage.handle(Services.GEOMETRY_TOPIC, poisoned)
        assertEquals(RunStatus.FAILED, runs[runId]?.status)
    }

    @Test
    fun unknownRunEventsAreIgnored() {
        val stage = monitor()
        stage.handle(Services.GEOMETRY_TOPIC, stageEvent(Services.GEOMETRY_TOPIC, "ghost", "g0", 10, 20))
        assertTrue(runs.isEmpty())
    }

    @Test
    fun wrongTopicIsIgnored() {
        val runId = UUID.randomUUID().toString()
        runs[runId] = RunState(runId, RunStatus.GENERATING_GEOMETRY, "Hello World", "key", java.time.Instant.now())
        val stage = monitor()
        stage.registerRun(runId, 1)
        stage.handle("rg.some-other.v1", stageEvent(Services.GEOMETRY_TOPIC, runId, "g0", 10, 20))
        assertEquals(RunStatus.GENERATING_GEOMETRY, runs[runId]?.status)
    }

    @Test
    fun malformedEventIsIgnored() {
        val runId = UUID.randomUUID().toString()
        runs[runId] = RunState(runId, RunStatus.GENERATING_GEOMETRY, "Hello World", "key", java.time.Instant.now())
        val stage = monitor()
        stage.registerRun(runId, 1)
        stage.handle(Services.GEOMETRY_TOPIC, "not json")
        assertEquals(RunStatus.GENERATING_GEOMETRY, runs[runId]?.status)
    }

    @Test
    fun eventWithoutCorrelationIdUsesDataRunId() {
        val runId = UUID.randomUUID().toString()
        runs[runId] = RunState(runId, RunStatus.GENERATING_GEOMETRY, "Hello World", "key", java.time.Instant.now())
        val stage = monitor()
        stage.registerRun(runId, 1)

        val noCorrelation = stageEvent(Services.GEOMETRY_TOPIC, runId, "g0", 10, 20).replaceFirst("\"correlationid\": \"$runId\",", "")
        stage.handle(Services.GEOMETRY_TOPIC, noCorrelation)
        assertEquals(RunStatus.NORMALIZING, runs[runId]?.status, "data.runId must resolve the run")
    }

    @Test
    fun eventWithoutRunContextIsIgnored() {
        val stage = monitor()
        stage.handle(Services.GEOMETRY_TOPIC, """{"specversion":"1.0","data":{}}""")
        assertTrue(runs.isEmpty())
    }

    @Test
    fun assemblyCompletesRunWithMatch() {
        val runId = UUID.randomUUID().toString()
        runs[runId] = RunState(runId, RunStatus.ASSEMBLING, "Hello World", "key", java.time.Instant.now())
        expectedTexts[runId] = "Hello World"
        val store = FakeRunStateStore()
        Services.runStateStore = store
        val producer = FakeEventProducer()
        Services.eventProducer = producer
        val stage = monitor()
        stage.registerRun(runId, 11, drawableCount = 10)

        stage.handle(Services.PHRASE_ASSEMBLED_TOPIC, assemblyEvent(runId, "Hello World"))
        assertEquals(RunStatus.SUCCEEDED, runs[runId]?.status, "matching assembly completes the run")
    }

    @Test
    fun assemblyMismatchFailsRun() {
        val runId = UUID.randomUUID().toString()
        runs[runId] = RunState(runId, RunStatus.ASSEMBLING, "Hello World", "key", java.time.Instant.now())
        expectedTexts[runId] = "Hello World"
        val stage = monitor()
        stage.registerRun(runId, 11, drawableCount = 10)

        stage.handle(Services.PHRASE_ASSEMBLED_TOPIC, assemblyEvent(runId, "Hello W0rld"))
        assertEquals(RunStatus.FAILED, runs[runId]?.status, "mismatched assembly fails the run")
    }

    @Test
    fun assemblyWithWrongMaturityFailsRun() {
        val runId = UUID.randomUUID().toString()
        runs[runId] = RunState(runId, RunStatus.ASSEMBLING, "Hello World", "key", java.time.Instant.now())
        expectedTexts[runId] = "Hello World"
        val stage = monitor()
        stage.registerRun(runId, 11, drawableCount = 10)

        stage.handle(Services.PHRASE_ASSEMBLED_TOPIC, assemblyEvent(runId, "Hello World", 70, 80))
        assertEquals(RunStatus.FAILED, runs[runId]?.status, "wrong maturity fails the run")
    }
}
