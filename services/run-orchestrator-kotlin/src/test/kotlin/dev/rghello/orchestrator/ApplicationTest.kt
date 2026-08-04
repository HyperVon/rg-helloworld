package dev.rghello.orchestrator

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.io.ByteArrayOutputStream
import java.io.PrintStream
import java.nio.charset.StandardCharsets

class ApplicationTest {
    private fun streams(): Pair<ByteArrayOutputStream, ByteArrayOutputStream> = ByteArrayOutputStream() to ByteArrayOutputStream()

    @Test
    fun versionCommandPrintsVersionToStdout() {
        val (out, err) = streams()
        val code = run(PrintStream(out, true, StandardCharsets.UTF_8), PrintStream(err, true, StandardCharsets.UTF_8), arrayOf("version"))

        assertEquals(0, code)
        assertEquals("run-orchestrator 0.0.0-skeleton\n", out.toString(StandardCharsets.UTF_8))
        assertEquals("", err.toString(StandardCharsets.UTF_8))
    }

    @Test
    fun unknownCommandReportsUsageOnStderr() {
        val (out, err) = streams()
        val code = run(PrintStream(out, true, StandardCharsets.UTF_8), PrintStream(err, true, StandardCharsets.UTF_8), arrayOf("run"))

        assertEquals(0, code)
        assertEquals("", out.toString(StandardCharsets.UTF_8))
        assertTrue(err.toString(StandardCharsets.UTF_8).contains("Milestone 0"))
        assertTrue(err.toString(StandardCharsets.UTF_8).contains("usage:"))
    }

    @Test
    fun extraArgumentsFallThroughToUsage() {
        val (out, err) = streams()
        val code =
            run(PrintStream(out, true, StandardCharsets.UTF_8), PrintStream(err, true, StandardCharsets.UTF_8), arrayOf("version", "extra"))

        assertEquals(0, code)
        assertEquals("", out.toString(StandardCharsets.UTF_8))
        assertTrue(err.toString(StandardCharsets.UTF_8).contains("usage:"))
    }
}
