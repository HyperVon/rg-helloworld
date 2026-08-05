package dev.rghello.catalog;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import dev.rghello.catalog.contract.Glyph;
import dev.rghello.catalog.contract.PlanPhraseResponse;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.embedded.EmbeddedDatabaseBuilder;
import org.springframework.jdbc.datasource.embedded.EmbeddedDatabaseType;
import tools.jackson.databind.ObjectMapper;

class GlyphCatalogServiceTest {

  private GlyphCatalogService service;
  private JdbcTemplate jdbc;

  @BeforeEach
  void setUp() {
    jdbc =
        new JdbcTemplate(
            new EmbeddedDatabaseBuilder()
                .generateUniqueName(true)
                .setType(EmbeddedDatabaseType.H2)
                .addScript("classpath:schema.sql")
                .build());
    service =
        new GlyphCatalogService(new PhrasePlanner(), new PlanRepository(jdbc, new ObjectMapper()));
  }

  @Test
  void planIsPersisted() {
    PlanPhraseResponse plan = service.planPhrase("Hello World", "RUBE_SIMPLEX_V1", "PRIMARY");

    Integer stored = jdbc.queryForObject("SELECT COUNT(*) FROM glyph_plans", Integer.class);
    assertEquals(1, stored);
    assertNotNull(plan.getPlanId());
  }

  @Test
  void alternateBlueprintComesFromStoredPlan() {
    PlanPhraseResponse plan = service.planPhrase("Hello", "RUBE_SIMPLEX_V1", "PRIMARY");
    Glyph first = plan.getGlyphs().getGlyph().get(0);

    PlanPhraseResponse alternate =
        service.getAlternateBlueprint(plan.getPlanId(), first.getGlyphInstanceId(), "PRIMARY");

    assertEquals(plan.getPlanId(), alternate.getPlanId());
    assertEquals(1, alternate.getGlyphs().getGlyph().size());
    assertEquals(
        first.getGlyphInstanceId(), alternate.getGlyphs().getGlyph().get(0).getGlyphInstanceId());
    assertNotEquals(
        first.getPrimitives().getPrimitive().get(0).getPoints().get(0).getX(),
        alternate
            .getGlyphs()
            .getGlyph()
            .get(0)
            .getPrimitives()
            .getPrimitive()
            .get(0)
            .getPoints()
            .get(0)
            .getX(),
        1e-9);
  }

  @Test
  void alternateExcludesRequestedVariant() {
    PlanPhraseResponse plan = service.planPhrase("Hello", "RUBE_SIMPLEX_V1", "PRIMARY");
    Glyph first = plan.getGlyphs().getGlyph().get(0);

    PlanPhraseResponse mirrored =
        service.getAlternateBlueprint(plan.getPlanId(), first.getGlyphInstanceId(), "PRIMARY");
    PlanPhraseResponse rotated =
        service.getAlternateBlueprint(plan.getPlanId(), first.getGlyphInstanceId(), "MIRRORED_X");

    assertNotEquals(
        mirrored
            .getGlyphs()
            .getGlyph()
            .get(0)
            .getPrimitives()
            .getPrimitive()
            .get(0)
            .getPoints()
            .get(0)
            .getY(),
        rotated
            .getGlyphs()
            .getGlyph()
            .get(0)
            .getPrimitives()
            .getPrimitive()
            .get(0)
            .getPoints()
            .get(0)
            .getY(),
        1e-9);
  }

  @Test
  void alternateForGapReturnsGap() {
    PlanPhraseResponse plan = service.planPhrase("Hello World", "RUBE_SIMPLEX_V1", "PRIMARY");
    Glyph gap = plan.getGlyphs().getGlyph().get(5);

    PlanPhraseResponse alternate =
        service.getAlternateBlueprint(plan.getPlanId(), gap.getGlyphInstanceId(), "PRIMARY");

    assertEquals("GAP", alternate.getGlyphs().getGlyph().get(0).getKind());
    assertTrue(alternate.getGlyphs().getGlyph().get(0).getPrimitives().getPrimitive().isEmpty());
  }

  @Test
  void unknownPlanFaults() {
    assertThrows(
        PlanNotFoundException.class,
        () ->
            service.getAlternateBlueprint("00000000-0000-0000-0000-000000000000", "x", "PRIMARY"));
  }

  @Test
  void unknownGlyphFaults() {
    PlanPhraseResponse plan = service.planPhrase("Hello", "RUBE_SIMPLEX_V1", "PRIMARY");
    assertThrows(
        GlyphNotFoundException.class,
        () -> service.getAlternateBlueprint(plan.getPlanId(), "not-a-glyph", "PRIMARY"));
  }

  @Test
  void plansAreDistinct() {
    PlanPhraseResponse first = service.planPhrase("Hello", "RUBE_SIMPLEX_V1", "PRIMARY");
    PlanPhraseResponse second = service.planPhrase("World", "RUBE_SIMPLEX_V1", "PRIMARY");
    assertNotEquals(first.getPlanId(), second.getPlanId());
  }
}
