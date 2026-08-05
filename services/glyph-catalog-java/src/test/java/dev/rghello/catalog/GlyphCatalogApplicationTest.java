package dev.rghello.catalog;

import static org.junit.jupiter.api.Assertions.assertEquals;

import java.io.ByteArrayOutputStream;
import java.io.PrintStream;
import java.nio.charset.StandardCharsets;
import org.junit.jupiter.api.Test;

class GlyphCatalogApplicationTest {

  @Test
  void versionCommandPrintsVersionToStdout() {
    var out = new ByteArrayOutputStream();
    var originalOut = System.out;
    try {
      System.setOut(new PrintStream(out, true, StandardCharsets.UTF_8));
      GlyphCatalogApplication.main(new String[] {"version"});
    } finally {
      System.setOut(originalOut);
    }
    assertEquals(
        "glyph-catalog 0.1.0-milestone4" + System.lineSeparator(),
        out.toString(StandardCharsets.UTF_8));
  }
}
