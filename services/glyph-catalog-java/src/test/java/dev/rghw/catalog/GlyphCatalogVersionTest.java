package dev.rghw.catalog;

import static org.junit.jupiter.api.Assertions.assertEquals;

import org.junit.jupiter.api.Test;

class GlyphCatalogVersionTest {

  @Test
  void versionMatchesMilestone4() {
    assertEquals("0.1.0-milestone4", GlyphCatalogVersion.VERSION);
  }
}
