#include <cmath>
#include <iostream>
#include <string>

#include "geometry_engine/geometry.hpp"
#include "geometry_engine/sha256.hpp"

namespace {

int failures = 0;

void expect(bool condition, const std::string& message) {
  if (!condition) {
    std::cerr << "FAIL: " << message << '\n';
    ++failures;
  }
}

void expectNear(double actual, double expected, const std::string& message) {
  if (std::fabs(actual - expected) > 1e-9) {
    std::cerr << "FAIL: " << message << " expected " << expected << " got " << actual << '\n';
    ++failures;
  }
}

rghello::Primitive polyline(std::initializer_list<rghello::Point> points) {
  rghello::Primitive primitive;
  primitive.type = "POLYLINE";
  primitive.points = points;
  return primitive;
}

}  // namespace

int main() {
  // POLYLINE expansion: N points -> N-1 segments.
  rghello::Primitive line = polyline({{0.0, 0.0}, {1.0, 0.0}, {1.0, 1.0}});
  std::vector<rghello::Segment> expanded = rghello::expandPrimitive(line, 12);
  expect(expanded.size() == 2, "polyline expands to N-1 segments");
  expect(expanded[0].x2 == 1.0 && expanded[0].y2 == 0.0, "first segment endpoint");

  // POINT contributes no segments.
  rghello::Primitive point;
  point.type = "POINT";
  point.points = {{0.5, 0.5}};
  expect(rghello::expandPrimitive(point, 12).empty(), "point expands to nothing");

  // ARC: quarter circle from (1,0) to (0,1) around origin, 4 subdivisions.
  rghello::Primitive arc;
  arc.type = "ARC";
  arc.points = {{1.0, 0.0}, {0.0, 1.0}, {0.0, 0.0}};
  std::vector<rghello::Segment> arcSegments = rghello::expandPrimitive(arc, 4);
  expect(arcSegments.size() == 4, "arc uses requested subdivisions");
  expect(arcSegments.front().x1 == 1.0 && arcSegments.front().y1 == 0.0, "arc starts at start");
  expect(arcSegments.back().x2 == 0.0 && arcSegments.back().y2 == 1.0, "arc ends at end");
  expectNear(arcSegments[0].x2, std::cos(M_PI / 8.0), "arc midpoint angle");
  try {
    rghello::Primitive badArc = arc;
    badArc.points = {{0.0, 0.0}, {1.0, 0.0}};
    (void)rghello::expandPrimitive(badArc, 4);
    std::cerr << "FAIL: short ARC should throw\n";
    ++failures;
  } catch (const std::invalid_argument&) {
  }

  // Zero-length segments are removed.
  rghello::Primitive degenerate = polyline({{0.0, 0.0}, {0.0, 0.0}, {1.0, 0.0}});
  std::vector<rghello::Segment> cleaned =
      rghello::cleanSegments(rghello::expandPrimitive(degenerate, 12));
  expect(cleaned.size() == 1, "zero-length segment removed");

  // Non-finite coordinates are dropped.
  std::vector<rghello::Segment> dirty = {
      {0.0, 0.0, 1.0, 1.0}, {0.0, 0.0, NAN, 1.0}, {0.0, 0.0, 1.0, INFINITY}};
  std::vector<rghello::Segment> finiteOnly = rghello::cleanSegments(dirty);
  expect(finiteOnly.size() == 1, "non-finite segments dropped");

  // Exactly collinear adjacent segments merge when the shared point is
  // between the endpoints.
  std::vector<rghello::Segment> collinear = {{0.0, 0.0, 1.0, 0.0}, {1.0, 0.0, 2.0, 0.0}};
  std::vector<rghello::Segment> merged = rghello::cleanSegments(collinear);
  expect(merged.size() == 1, "collinear segments merge");
  expect(merged[0].x2 == 2.0, "merge spans both segments");

  // Backtracking collinear segments (shared point outside the span) do not
  // merge because the union would change shape.
  std::vector<rghello::Segment> backtrack = {{0.0, 0.0, 2.0, 0.0}, {2.0, 0.0, 1.0, 0.0}};
  std::vector<rghello::Segment> kept = rghello::cleanSegments(backtrack);
  expect(kept.size() == 2, "backtracking collinear segments are kept");

  // Non-collinear adjacent segments stay separate.
  std::vector<rghello::Segment> corner = {{0.0, 0.0, 1.0, 0.0}, {1.0, 0.0, 1.0, 1.0}};
  expect(rghello::cleanSegments(corner).size() == 2, "corner segments are kept");

  // Stats: bounding box, length, count for a known shape.
  std::vector<rghello::Segment> shape =
      rghello::cleanSegments({{0.0, 0.0, 3.0, 4.0}, {3.0, 4.0, 3.0, 4.0}});
  rghello::GeometryStats stats = rghello::computeStats(shape);
  expectNear(stats.totalLength, 5.0, "path length");
  expect(stats.segmentCount == 1, "segment count after cleaning");  // zero-length excluded
  expectNear(stats.xMin, 0.0, "xMin");
  expectNear(stats.yMin, 0.0, "yMin");
  expectNear(stats.xMax, 3.0, "xMax");
  expectNear(stats.yMax, 4.0, "yMax");

  // Intersection counting: proper crossings only.
  std::vector<rghello::Segment> crossing = {{0.0, 0.0, 2.0, 2.0}, {0.0, 2.0, 2.0, 0.0}};
  expect(rghello::computeStats(crossing).intersectionCount == 1, "crossing segments intersect");
  std::vector<rghello::Segment> touching = {{0.0, 0.0, 2.0, 2.0}, {2.0, 2.0, 4.0, 4.0}};
  expect(rghello::computeStats(touching).intersectionCount == 0,
         "shared endpoints do not intersect");

  // Empty segments produce an empty (zero) stats record.
  rghello::GeometryStats empty = rghello::computeStats({});
  expect(empty.segmentCount == 0 && empty.totalLength == 0.0, "empty stats");

  // Artifact JSON builders are canonical and hash-stable.
  rghello::Json gap = rghello::gapGeometryJson(0.6, 0.0, 0.0);
  expect(gap.serialize() ==
             "{\"advanceWidth\":0.6,\"kind\":\"GAP_GEOMETRY\",\"leftBearing\":0,"
             "\"rightBearing\":0}",
         "gap artifact canonical json");
  rghello::Json drawable = rghello::drawableGeometryJson(shape, stats, 1.0);
  expect(drawable.at("kind").asString() == "DRAWABLE_GEOMETRY", "drawable kind");
  expect(drawable.at("segmentCount").asInt64() == 1, "drawable segment count");
  expect(drawable.at("advanceWidth").asNumber() == 1.0, "drawable advance width");
  expect(drawable.serialize() == rghello::drawableGeometryJson(shape, stats, 1.0).serialize(),
         "drawable artifact is deterministic");

  // Blueprint parsing: drawable and gap payloads.
  rghello::Json data = rghello::Json::parse(
      "{\"runId\":\"11111111-1111-4111-8111-111111111111\",\"planId\":\"22222222-2222-4222-8222-"
      "222222222222\",\"stepId\":\"33333333-3333-4333-8333-333333333333\",\"attempt\":1,"
      "\"inputArtifacts\":[],\"outputArtifacts\":[],\"transformation\":{\"name\":\"plan-glyphs\","
      "\"version\":\"1.0.0\"},\"glyphs\":[{\"glyphInstanceId\":\"44444444-4444-4444-8444-"
      "444444444444\",\"position\":0,\"kind\":\"DRAWABLE\",\"advanceWidth\":1.0,\"primitives\":["
      "{\"type\":\"POLYLINE\",\"points\":[{\"x\":0.1,\"y\":0.0},{\"x\":0.1,\"y\":1.0}]}]}]}");
  rghello::BlueprintGlyph glyph = rghello::parseBlueprintGlyph(data);
  expect(glyph.glyphInstanceId == "44444444-4444-4444-8444-444444444444", "glyph id parsed");
  expect(glyph.position == 0 && glyph.kind == "DRAWABLE", "position and kind parsed");
  expect(glyph.primitives.size() == 1 && glyph.primitives[0].points.size() == 2,
         "primitives parsed");
  try {
    rghello::parseBlueprintGlyph(rghello::Json::parse("{\"glyphs\":[]}"));
    std::cerr << "FAIL: empty glyphs array should throw\n";
    ++failures;
  } catch (const std::invalid_argument&) {
  }

  // sameGeometry comparison.
  expect(rghello::sameGeometry(crossing, crossing), "identical geometry matches");
  expect(!rghello::sameGeometry(crossing, touching), "different geometry differs");

  if (failures == 0) {
    std::cout << "geometry tests passed\n";
    return 0;
  }
  std::cerr << failures << " geometry test(s) failed\n";
  return 1;
}
