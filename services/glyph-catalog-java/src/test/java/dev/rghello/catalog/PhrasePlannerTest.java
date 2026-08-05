package dev.rghello.catalog;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import dev.rghello.catalog.contract.Glyph;
import dev.rghello.catalog.contract.PlanPhraseResponse;
import org.junit.jupiter.api.Test;

class PhrasePlannerTest {

  private final PhrasePlanner planner = new PhrasePlanner();

  @Test
  void helloWorldProducesElevenOrderedGlyphs() {
    PlanPhraseResponse plan = planner.plan("Hello World", "RUBE_SIMPLEX_V1", "PRIMARY");

    assertEquals(11, plan.getGlyphs().getGlyph().size());
    for (int i = 0; i < plan.getGlyphs().getGlyph().size(); i++) {
      assertEquals(i, plan.getGlyphs().getGlyph().get(i).getPosition());
    }
  }

  @Test
  void gapPositionExistsWithWidthAndNoPrimitives() {
    PlanPhraseResponse plan = planner.plan("Hello World", "RUBE_SIMPLEX_V1", "PRIMARY");

    Glyph gap = plan.getGlyphs().getGlyph().get(5);
    assertEquals("GAP", gap.getKind());
    assertEquals(0.6, gap.getAdvanceWidth());
    assertTrue(gap.getPrimitives().getPrimitive().isEmpty());
  }

  @Test
  void drawableGlyphsHaveExpectedGeometry() {
    PlanPhraseResponse plan = planner.plan("Hello World", "RUBE_SIMPLEX_V1", "PRIMARY");

    Glyph h = plan.getGlyphs().getGlyph().get(0);
    assertEquals("DRAWABLE", h.getKind());
    assertEquals(3, h.getPrimitives().getPrimitive().size());
    assertEquals(2, h.getPrimitives().getPrimitive().get(0).getPoints().size());

    Glyph o = plan.getGlyphs().getGlyph().get(7);
    assertEquals(16, o.getPrimitives().getPrimitive().get(0).getPoints().size());

    Glyph w = plan.getGlyphs().getGlyph().get(6);
    assertEquals(4, w.getPrimitives().getPrimitive().size());

    Glyph l = plan.getGlyphs().getGlyph().get(2);
    assertEquals(2, l.getPrimitives().getPrimitive().size());
  }

  @Test
  void instanceIdsAreOpaqueUuids() {
    PlanPhraseResponse plan = planner.plan("Hello World", "RUBE_SIMPLEX_V1", "PRIMARY");

    assertTrue(
        plan.getGlyphs()
            .getGlyph()
            .get(0)
            .getGlyphInstanceId()
            .matches(
                "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"));
    assertFalse(
        plan.getGlyphs()
            .getGlyph()
            .get(0)
            .getGlyphInstanceId()
            .equals(plan.getGlyphs().getGlyph().get(1).getGlyphInstanceId()));
  }

  @Test
  void unsupportedCharacterFaults() {
    assertThrows(
        UnsupportedCharacterException.class,
        () -> planner.plan("Hello World!", "RUBE_SIMPLEX_V1", "PRIMARY"));
  }

  @Test
  void unknownAlphabetFaults() {
    assertThrows(
        UnsupportedAlphabetException.class,
        () -> planner.plan("Hello", "SOME_OTHER_V1", "PRIMARY"));
  }

  @Test
  void unknownVariantFaults() {
    assertThrows(
        UnsupportedVariantException.class,
        () -> planner.plan("Hello", "RUBE_SIMPLEX_V1", "DOUBLE_SIZE"));
  }

  @Test
  void emptyMessageProducesEmptyPlan() {
    PlanPhraseResponse plan = planner.plan("", "RUBE_SIMPLEX_V1", "PRIMARY");
    assertTrue(plan.getGlyphs().getGlyph().isEmpty());
  }
}
