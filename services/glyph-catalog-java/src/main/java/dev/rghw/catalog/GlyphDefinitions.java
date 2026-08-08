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
  static final double GAP_WIDTH = 1.0;

  record GlyphDef(double advanceWidth, List<Primitive> primitives) {}

  static final Map<Character, GlyphDef> DEFINITIONS = build();

  private GlyphDefinitions() {}

  private static Map<Character, GlyphDef> build() {
    Map<Character, GlyphDef> glyphs = new LinkedHashMap<>();
    glyphs.put(
        'H',
        drawable(
            1.0,
            line(0.2, 0.1, 0.2, 0.9),
            line(0.8, 0.1, 0.8, 0.9),
            line(0.2, 0.5, 0.8, 0.5),
            line(0.14, 0.1, 0.26, 0.1),
            line(0.74, 0.1, 0.86, 0.1),
            line(0.14, 0.9, 0.26, 0.9),
            line(0.74, 0.9, 0.86, 0.9)));
    glyphs.put(
        'E',
        drawable(
            1.0,
            line(0.18, 0.1, 0.18, 0.9),
            line(0.20, 0.1, 0.20, 0.9),
            line(0.22, 0.1, 0.22, 0.9),
            line(0.24, 0.1, 0.24, 0.9),
            line(0.26, 0.1, 0.26, 0.9),
            line(0.20, 0.08, 0.82, 0.08),
            line(0.20, 0.10, 0.82, 0.10),
            line(0.20, 0.12, 0.82, 0.12),
            line(0.20, 0.48, 0.70, 0.48),
            line(0.20, 0.50, 0.70, 0.50),
            line(0.20, 0.52, 0.70, 0.52),
            line(0.20, 0.88, 0.82, 0.88),
            line(0.20, 0.90, 0.82, 0.90),
            line(0.20, 0.92, 0.82, 0.92)));
    glyphs.put(
        'L',
        drawable(
            1.0,
            line(0.2, 0.1, 0.2, 0.9),
            line(0.2, 0.1, 0.8, 0.1),
            line(0.14, 0.1, 0.26, 0.1),
            line(0.14, 0.9, 0.26, 0.9)));
    glyphs.put(
        'O',
        drawable(
            1.0,
            ellipse(0.5, 0.5, 0.30, 0.40, 20),
            ellipse(0.5, 0.5, 0.28, 0.38, 20),
            ellipse(0.5, 0.5, 0.32, 0.42, 20)));
    glyphs.put(
        'W',
        drawable(
            1.0,
            path(0.12, 0.2, 0.25, 0.85, 0.40, 0.25, 0.50, 0.85, 0.65, 0.2, 0.88, 0.85),
            path(0.14, 0.2, 0.27, 0.85, 0.42, 0.25, 0.52, 0.85, 0.67, 0.2, 0.90, 0.85),
            path(0.10, 0.2, 0.23, 0.85, 0.38, 0.25, 0.48, 0.85, 0.63, 0.2, 0.86, 0.85)));
    glyphs.put(
        'R',
        drawable(
            1.0,
            line(0.2, 0.1, 0.2, 0.9),
            path(0.2, 0.9, 0.55, 0.9, 0.7, 0.82, 0.78, 0.70, 0.76, 0.58, 0.66, 0.5, 0.2, 0.5),
            line(0.45, 0.50, 0.80, 0.10),
            line(0.14, 0.1, 0.26, 0.1)));
    glyphs.put(
        'D',
        drawable(
            1.0,
            line(0.18, 0.1, 0.18, 0.9),
            line(0.20, 0.1, 0.20, 0.9),
            line(0.22, 0.1, 0.22, 0.9),
            path(
                0.2, 0.1, 0.55, 0.1, 0.68, 0.18, 0.77, 0.3, 0.8, 0.5, 0.77, 0.7, 0.68, 0.82, 0.55,
                0.9, 0.2, 0.9),
            path(
                0.2, 0.12, 0.55, 0.12, 0.68, 0.20, 0.77, 0.32, 0.8, 0.52, 0.77, 0.72, 0.68, 0.84,
                0.55, 0.92, 0.2, 0.92),
            line(0.14, 0.1, 0.26, 0.1),
            line(0.14, 0.9, 0.26, 0.9)));
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

  private static Primitive path(double... coordinates) {
    Primitive primitive = new Primitive();
    primitive.setType(POLYLINE);
    for (int i = 0; i < coordinates.length; i += 2) {
      primitive.getPoints().add(point(coordinates[i], coordinates[i + 1]));
    }
    return primitive;
  }

  private static Primitive polygon(double cx, double cy, double radius, int sides) {
    return ellipse(cx, cy, radius, radius, sides);
  }

  private static Primitive ellipse(
      double cx, double cy, double radiusX, double radiusY, int sides) {
    Primitive primitive = new Primitive();
    primitive.setType(POLYLINE);
    for (int i = 0; i <= sides; i++) {
      double angle = 2.0 * Math.PI * (i % sides) / sides;
      primitive
          .getPoints()
          .add(point(cx + radiusX * Math.cos(angle), cy + radiusY * Math.sin(angle)));
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
