package dev.rghello.orchestrator

import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import java.io.ByteArrayOutputStream
import java.io.PrintStream
import java.nio.charset.StandardCharsets
import java.util.concurrent.atomic.AtomicInteger

class ApplicationMainTest {
    private val originalOut = System.out
    private val originalErr = System.err
    private lateinit var outBuf: ByteArrayOutputStream
    private lateinit var errBuf: ByteArrayOutputStream

    @BeforeEach
    fun redirectStreams() {
        outBuf = ByteArrayOutputStream()
        errBuf = ByteArrayOutputStream()
        System.setOut(PrintStream(outBuf, true, StandardCharsets.UTF_8))
        System.setErr(PrintStream(errBuf, true, StandardCharsets.UTF_8))
    }

    @AfterEach
    fun restoreStreams() {
        System.setOut(originalOut)
        System.setErr(originalErr)
        exit = { code -> kotlin.system.exitProcess(code) }
    }

    @Test
    fun mainVersionExitsZero() {
        val captured = AtomicInteger(-1)
        exit = { captured.set(it) }
        main(arrayOf("version"))
        assertEquals(0, captured.get())
        assertEquals("run-orchestrator 0.3.0-milestone5\n", outBuf.toString(StandardCharsets.UTF_8))
    }

    @Test
    fun mainVersionWithExtraArgsExitsZero() {
        val captured = AtomicInteger(-1)
        exit = { captured.set(it) }
        main(arrayOf("version", "extra"))
        assertEquals(0, captured.get())
        assertEquals("run-orchestrator 0.3.0-milestone5\n", outBuf.toString(StandardCharsets.UTF_8))
    }
}
