package dev.rghello.catalog;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.io.ByteArrayOutputStream;
import java.io.PrintStream;
import java.nio.charset.StandardCharsets;
import org.junit.jupiter.api.Test;

class GlyphCatalogApplicationTest {

  @Test
  void versionCommandPrintsVersionToStdout() {
    var out = new ByteArrayOutputStream();
    var err = new ByteArrayOutputStream();
    int code =
        GlyphCatalogApplication.run(
            new PrintStream(out, true, StandardCharsets.UTF_8),
            new PrintStream(err, true, StandardCharsets.UTF_8),
            new String[] {"version"});

    assertEquals(0, code);
    assertEquals(
        "glyph-catalog 0.0.0-skeleton%n".formatted(), out.toString(StandardCharsets.UTF_8));
    assertEquals("", err.toString(StandardCharsets.UTF_8));
  }

  @Test
  void unknownCommandReportsUsageOnStderr() {
    var out = new ByteArrayOutputStream();
    var err = new ByteArrayOutputStream();
    int code =
        GlyphCatalogApplication.run(
            new PrintStream(out, true, StandardCharsets.UTF_8),
            new PrintStream(err, true, StandardCharsets.UTF_8),
            new String[] {"run"});

    assertEquals(0, code);
    assertEquals("", out.toString(StandardCharsets.UTF_8));
    var stderr = err.toString(StandardCharsets.UTF_8);
    assertTrue(stderr.contains("Milestone 0"));
    assertTrue(stderr.contains("usage:"));
  }

  @Test
  void extraArgumentsFallThroughToUsage() {
    var out = new ByteArrayOutputStream();
    var err = new ByteArrayOutputStream();
    int code =
        GlyphCatalogApplication.run(
            new PrintStream(out, true, StandardCharsets.UTF_8),
            new PrintStream(err, true, StandardCharsets.UTF_8),
            new String[] {"version", "extra"});

    assertEquals(0, code);
    assertEquals("", out.toString(StandardCharsets.UTF_8));
    assertTrue(err.toString(StandardCharsets.UTF_8).contains("usage:"));
  }
}
