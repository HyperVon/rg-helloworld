package dev.rghw.catalog;

import dev.rghw.catalog.contract.Glyph;
import dev.rghw.catalog.contract.Glyphs;
import dev.rghw.catalog.contract.PlanPhraseResponse;
import dev.rghw.catalog.contract.Point;
import dev.rghw.catalog.contract.Primitive;
import dev.rghw.catalog.contract.Primitives;
import java.util.List;
import org.springframework.stereotype.Service;

@Service
public class GlyphCatalogService {

  enum Variant {
    PRIMARY,
    MIRRORED_X,
    ROTATED_180
  }

  private static final List<Variant> ALTERNATES =
      List.of(Variant.MIRRORED_X, Variant.ROTATED_180, Variant.PRIMARY);

  private final PhrasePlanner planner;
  private final PlanRepository repository;

  public GlyphCatalogService(PhrasePlanner planner, PlanRepository repository) {
    this.planner = planner;
    this.repository = repository;
  }

  public PlanPhraseResponse planPhrase(String message, String alphabet, String variant) {
    PlanPhraseResponse plan = planner.plan(message, alphabet, variant);
    repository.save(plan);
    return plan;
  }

  public PlanPhraseResponse getAlternateBlueprint(
      String planId, String glyphInstanceId, String excludedVariant) {
    PlanPhraseResponse plan = repository.findById(planId);
    if (plan == null) {
      throw new PlanNotFoundException(planId);
    }
    Glyph glyph =
        plan.getGlyphs().getGlyph().stream()
            .filter(candidate -> candidate.getGlyphInstanceId().equals(glyphInstanceId))
            .findFirst()
            .orElseThrow(() -> new GlyphNotFoundException(glyphInstanceId));
    PlanPhraseResponse response = new PlanPhraseResponse();
    response.setPlanId(planId);
    Glyphs wrapper = new Glyphs();
    wrapper.getGlyph().add(transform(glyph, alternate(excludedVariant)));
    response.setGlyphs(wrapper);
    return response;
  }

  private static Variant alternate(String excludedVariant) {
    for (Variant variant : ALTERNATES) {
      if (!variant.name().equals(excludedVariant)) {
        return variant;
      }
    }
    return Variant.PRIMARY;
  }

  private static Glyph transform(Glyph source, Variant variant) {
    Glyph transformed = new Glyph();
    transformed.setGlyphInstanceId(source.getGlyphInstanceId());
    transformed.setPosition(source.getPosition());
    transformed.setKind(source.getKind());
    transformed.setAdvanceWidth(source.getAdvanceWidth());
    Primitives primitives = new Primitives();
    for (Primitive primitive : source.getPrimitives().getPrimitive()) {
      Primitive copy = new Primitive();
      copy.setType(primitive.getType());
      for (Point point : primitive.getPoints()) {
        copy.getPoints().add(transformPoint(point, variant));
      }
      primitives.getPrimitive().add(copy);
    }
    transformed.setPrimitives(primitives);
    return transformed;
  }

  private static Point transformPoint(Point point, Variant variant) {
    Point transformed = new Point();
    switch (variant) {
      case MIRRORED_X:
        transformed.setX(1.0 - point.getX());
        transformed.setY(point.getY());
        break;
      case ROTATED_180:
        transformed.setX(1.0 - point.getX());
        transformed.setY(1.0 - point.getY());
        break;
      default:
        transformed.setX(point.getX());
        transformed.setY(point.getY());
    }
    return transformed;
  }
}
