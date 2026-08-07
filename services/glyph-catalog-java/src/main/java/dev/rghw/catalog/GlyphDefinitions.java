package dev.rghw.catalog;

import dev.rghw.catalog.contract.Point;
import dev.rghw.catalog.contract.Primitive;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

final class GlyphDefinitions {

  static final String ALPHABET = "RUBE_SIMPLEX_V1";
  static final String POLYLINE = "POLYLINE";
  static final double GAP_WIDTH = 0.6;

  record GlyphDef(double advanceWidth, List<Primitive> primitives) {}

  static final Map<Character, GlyphDef> DEFINITIONS = build();

  private GlyphDefinitions() {}

  private static Map<Character, GlyphDef> build() {
    Map<Character, GlyphDef> glyphs = new LinkedHashMap<>();
    glyphs.put(
        'H',
        drawable(
            1.0, line(0.1, 0.0, 0.1, 1.0), line(0.9, 0.0, 0.9, 1.0), line(0.1, 0.5, 0.9, 0.5)));
    glyphs.put('e', drawable(1.0, polygon(0.55, 0.45, 0.35, 8), line(0.35, 0.5, 0.75, 0.5)));
    glyphs.put('l', drawable(1.0, line(0.5, 0.0, 0.5, 1.0), line(0.35, 0.0, 0.65, 0.0)));
    glyphs.put('o', drawable(1.0, polygon(0.5, 0.5, 0.4, 8)));
    glyphs.put(
        'W',
        drawable(
            1.0,
            line(0.1, 1.0, 0.35, 0.0),
            line(0.35, 0.0, 0.5, 0.55),
            line(0.5, 0.55, 0.65, 0.0),
            line(0.65, 0.0, 0.9, 1.0)));
    glyphs.put(
        'r',
        drawable(
            1.0,
            line(0.35, 0.0, 0.35, 1.0),
            line(0.35, 0.65, 0.75, 0.65),
            line(0.75, 0.65, 0.65, 0.35)));
    glyphs.put('d', drawable(1.0, line(0.65, 0.0, 0.65, 1.0), polygon(0.4, 0.35, 0.3, 8)));
    return glyphs;
  }

  private static GlyphDef drawable(double advanceWidth, Primitive... primitives) {
    return new GlyphDef(advanceWidth, List.of(primitives));
  }

  private static Primitive line(double x1, double y1, double x2, double y2) {
    Primitive primitive = new Primitive();
    primitive.setType(POLYLINE);
    primitive.getPoints().add(point(x1, y1));
    primitive.getPoints().add(point(x2, y2));
    return primitive;
  }

  private static Primitive polygon(double cx, double cy, double radius, int sides) {
    Primitive primitive = new Primitive();
    primitive.setType(POLYLINE);
    for (int i = 0; i < sides; i++) {
      double angle = 2.0 * Math.PI * i / sides;
      primitive
          .getPoints()
          .add(point(cx + radius * Math.cos(angle), cy + radius * Math.sin(angle)));
    }
    return primitive;
  }

  private static Point point(double x, double y) {
    Point point = new Point();
    point.setX(x);
    point.setY(y);
    return point;
  }

  static List<Primitive> copyPrimitives(GlyphDef def) {
    List<Primitive> primitives = new ArrayList<>();
    for (Primitive source : def.primitives()) {
      Primitive copy = new Primitive();
      copy.setType(source.getType());
      for (Point sourcePoint : source.getPoints()) {
        copy.getPoints().add(point(sourcePoint.getX(), sourcePoint.getY()));
      }
      primitives.add(copy);
    }
    return primitives;
  }
}
