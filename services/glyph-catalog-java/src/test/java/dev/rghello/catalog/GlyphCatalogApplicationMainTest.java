package dev.rghello.catalog;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.io.ByteArrayOutputStream;
import java.io.PrintStream;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

class GlyphCatalogApplicationMainTest {

  private final PrintStream originalOut = System.out;
  private final PrintStream originalErr = System.err;
  private ByteArrayOutputStream outBuf;
  private ByteArrayOutputStream errBuf;

  @BeforeEach
  void redirectStreams() {
    outBuf = new ByteArrayOutputStream();
    errBuf = new ByteArrayOutputStream();
    System.setOut(new PrintStream(outBuf, true, StandardCharsets.UTF_8));
    System.setErr(new PrintStream(errBuf, true, StandardCharsets.UTF_8));
  }

  @AfterEach
  void restoreStreams() {
    System.setOut(originalOut);
    System.setErr(originalErr);
  }

  @Test
  void mainVersionExitsZero() {
    AtomicInteger captured = new AtomicInteger(-1);
    GlyphCatalogApplication.exit = captured::set;
    try {
      GlyphCatalogApplication.main(new String[] {"version"});
    } finally {
      GlyphCatalogApplication.exit = System::exit;
    }
    assertEquals(0, captured.get());
    assertEquals(
        "glyph-catalog 0.0.0-skeleton" + System.lineSeparator(),
        outBuf.toString(StandardCharsets.UTF_8));
  }

  @Test
  void mainUnknownCommandWritesUsageToStderr() {
    AtomicInteger captured = new AtomicInteger(-1);
    GlyphCatalogApplication.exit = captured::set;
    try {
      GlyphCatalogApplication.main(new String[] {"run"});
    } finally {
      GlyphCatalogApplication.exit = System::exit;
    }
    assertEquals(0, captured.get());
    assertEquals("", outBuf.toString(StandardCharsets.UTF_8));
    String stderr = errBuf.toString(StandardCharsets.UTF_8);
    assertTrue(stderr.contains("Milestone 0"), "stderr: " + stderr);
    assertTrue(stderr.contains("usage:"), "stderr: " + stderr);
  }
}
