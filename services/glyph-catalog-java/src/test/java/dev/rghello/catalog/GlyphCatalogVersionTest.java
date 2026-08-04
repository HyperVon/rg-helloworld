package dev.rghello.catalog;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;

import org.junit.jupiter.api.Test;

class GlyphCatalogVersionTest {

  @Test
  void versionMatchesSkeleton() {
    assertEquals("0.0.0-skeleton", GlyphCatalogVersion.VERSION);
  }

  @Test
  void versionIsNotEmpty() {
    assertFalse(GlyphCatalogVersion.VERSION.isBlank());
  }
}
