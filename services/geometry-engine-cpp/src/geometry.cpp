#include "geometry_engine/geometry.hpp"

#include <cmath>
#include <cstdint>
#include <stdexcept>
#include <utility>

#include "geometry_engine/sha256.hpp"

namespace rghw {

namespace {

constexpr double kEpsilon = 1e-9;

bool finite(double value) { return std::isfinite(value); }

double cross(const Point& a, const Point& b, const Point& c) {
  return (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);
}

bool onSegment(const Point& p, const Point& q, const Point& r) {
  return q.x <= std::max(p.x, r.x) + kEpsilon && q.x >= std::min(p.x, r.x) - kEpsilon &&
         q.y <= std::max(p.y, r.y) + kEpsilon && q.y >= std::min(p.y, r.y) - kEpsilon;
}

// Proper crossing only: segments sharing an endpoint are not intersections.
bool properIntersect(const Segment& a, const Segment& b) {
  Point p1{a.x1, a.y1};
  Point p2{a.x2, a.y2};
  Point p3{b.x1, b.y1};
  Point p4{b.x2, b.y2};
  double d1 = cross(p3, p4, p1);
  double d2 = cross(p3, p4, p2);
  double d3 = cross(p1, p2, p3);
  double d4 = cross(p1, p2, p4);
  if (((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) && ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0))) {
    return true;
  }
  if (std::fabs(d1) < kEpsilon && onSegment(p3, p1, p4)) {
    return false;
  }
  if (std::fabs(d2) < kEpsilon && onSegment(p3, p2, p4)) {
    return false;
  }
  if (std::fabs(d3) < kEpsilon && onSegment(p1, p3, p2)) {
    return false;
  }
  if (std::fabs(d4) < kEpsilon && onSegment(p1, p4, p2)) {
    return false;
  }
  return false;
}

}  // namespace

std::vector<Segment> expandPrimitive(const Primitive& primitive, int arcSubdivisions) {
  std::vector<Segment> result;
  if (primitive.type == "POLYLINE") {
    for (size_t i = 0; i + 1 < primitive.points.size(); ++i) {
      result.push_back({primitive.points[i].x, primitive.points[i].y, primitive.points[i + 1].x,
                        primitive.points[i + 1].y});
    }
    return result;
  }
  if (primitive.type == "ARC") {
    // Contract: points = [start, end, center]; arc runs counter-clockwise
    // from start to end around center.
    if (primitive.points.size() < 3) {
      throw std::invalid_argument("ARC primitive requires start, end, and center points");
    }
    const Point& start = primitive.points[0];
    const Point& end = primitive.points[1];
    const Point& center = primitive.points[2];
    if (arcSubdivisions < 1) {
      throw std::invalid_argument("arc subdivisions must be >= 1");
    }
    double startAngle = std::atan2(start.y - center.y, start.x - center.x);
    double endAngle = std::atan2(end.y - center.y, end.x - center.x);
    double sweep = endAngle - startAngle;
    while (sweep <= 0.0) {
      sweep += 2.0 * M_PI;
    }
    double radius = std::hypot(start.x - center.x, start.y - center.y);
    double step = sweep / static_cast<double>(arcSubdivisions);
    Point previous = start;
    for (int i = 1; i <= arcSubdivisions; ++i) {
      double angle = startAngle + step * static_cast<double>(i);
      Point next{center.x + radius * std::cos(angle), center.y + radius * std::sin(angle)};
      if (i == arcSubdivisions) {
        next = end;
      }
      result.push_back({previous.x, previous.y, next.x, next.y});
      previous = next;
    }
    return result;
  }
  // POINT and unknown types contribute no segments.
  return result;
}

std::vector<Segment> cleanSegments(const std::vector<Segment>& input) {
  std::vector<Segment> cleaned;
  cleaned.reserve(input.size());
  for (const Segment& segment : input) {
    if (!finite(segment.x1) || !finite(segment.y1) || !finite(segment.x2) || !finite(segment.y2)) {
      continue;
    }
    if (segment.x1 == segment.x2 && segment.y1 == segment.y2) {
      continue;
    }
    cleaned.push_back(segment);
  }
  if (cleaned.size() < 2) {
    return cleaned;
  }
  bool merged = true;
  while (merged) {
    merged = false;
    std::vector<Segment> next;
    next.reserve(cleaned.size());
    size_t i = 0;
    while (i < cleaned.size()) {
      if (i + 1 < cleaned.size() && cleaned[i].x2 == cleaned[i + 1].x1 &&
          cleaned[i].y2 == cleaned[i + 1].y1) {
        Point a{cleaned[i].x1, cleaned[i].y1};
        Point b{cleaned[i].x2, cleaned[i].y2};
        Point c{cleaned[i + 1].x2, cleaned[i + 1].y2};
        // Merge only when the shared point lies strictly between the two
        // endpoints so the union of the two segments equals the merge.
        if (std::fabs(cross(a, b, c)) < kEpsilon && onSegment(a, b, c)) {
          next.push_back({a.x, a.y, c.x, c.y});
          merged = true;
          i += 2;
          continue;
        }
      }
      next.push_back(cleaned[i]);
      ++i;
    }
    cleaned = std::move(next);
  }
  return cleaned;
}

GeometryStats computeStats(const std::vector<Segment>& segments) {
  GeometryStats stats;
  if (segments.empty()) {
    return stats;
  }
  stats.xMin = segments.front().x1;
  stats.yMin = segments.front().y1;
  stats.xMax = segments.front().x1;
  stats.yMax = segments.front().y1;
  for (const Segment& segment : segments) {
    stats.xMin = std::min(stats.xMin, std::min(segment.x1, segment.x2));
    stats.yMin = std::min(stats.yMin, std::min(segment.y1, segment.y2));
    stats.xMax = std::max(stats.xMax, std::max(segment.x1, segment.x2));
    stats.yMax = std::max(stats.yMax, std::max(segment.y1, segment.y2));
    stats.totalLength += std::hypot(segment.x2 - segment.x1, segment.y2 - segment.y1);
  }
  stats.segmentCount = segments.size();
  for (size_t i = 0; i < segments.size(); ++i) {
    for (size_t j = i + 1; j < segments.size(); ++j) {
      if (properIntersect(segments[i], segments[j])) {
        ++stats.intersectionCount;
      }
    }
  }
  return stats;
}

Json drawableGeometryJson(const std::vector<Segment>& segments, const GeometryStats& stats,
                          double advanceWidth) {
  Json geometry = Json::object();
  geometry.objectItems()["kind"] = Json::str("DRAWABLE_GEOMETRY");
  Json segmentArray = Json::array();
  for (const Segment& segment : segments) {
    Json item = Json::object();
    item.objectItems()["x1"] = Json::number(segment.x1);
    item.objectItems()["y1"] = Json::number(segment.y1);
    item.objectItems()["x2"] = Json::number(segment.x2);
    item.objectItems()["y2"] = Json::number(segment.y2);
    segmentArray.arrayItems().push_back(std::move(item));
  }
  geometry.objectItems()["segments"] = std::move(segmentArray);
  Json bbox = Json::object();
  bbox.objectItems()["xMin"] = Json::number(stats.xMin);
  bbox.objectItems()["yMin"] = Json::number(stats.yMin);
  bbox.objectItems()["xMax"] = Json::number(stats.xMax);
  bbox.objectItems()["yMax"] = Json::number(stats.yMax);
  geometry.objectItems()["boundingBox"] = std::move(bbox);
  geometry.objectItems()["advanceWidth"] = Json::number(advanceWidth);
  geometry.objectItems()["leftBearing"] = Json::number(0.0);
  geometry.objectItems()["rightBearing"] = Json::number(0.0);
  geometry.objectItems()["totalLength"] = Json::number(stats.totalLength);
  geometry.objectItems()["segmentCount"] = Json::number(static_cast<double>(stats.segmentCount));
  geometry.objectItems()["intersectionCount"] =
      Json::number(static_cast<double>(stats.intersectionCount));
  return geometry;
}

Json gapGeometryJson(double advanceWidth, double leftBearing, double rightBearing) {
  Json geometry = Json::object();
  geometry.objectItems()["kind"] = Json::str("GAP_GEOMETRY");
  geometry.objectItems()["advanceWidth"] = Json::number(advanceWidth);
  geometry.objectItems()["leftBearing"] = Json::number(leftBearing);
  geometry.objectItems()["rightBearing"] = Json::number(rightBearing);
  return geometry;
}

BlueprintGlyph parseBlueprintGlyph(const Json& data) {
  const Json& glyphs = data.at("glyphs");
  if (!glyphs.isArray() || glyphs.arrayItems().empty()) {
    throw std::invalid_argument("blueprint event data has no glyphs array");
  }
  const Json& glyph = glyphs.arrayItems().front();
  BlueprintGlyph result;
  result.glyphInstanceId = glyph.at("glyphInstanceId").asString();
  result.position = static_cast<int>(glyph.at("position").asInt64());
  result.kind = glyph.at("kind").asString();
  result.advanceWidth = glyph.at("advanceWidth").asNumber();
  const Json& primitives = glyph.at("primitives");
  if (primitives.isArray()) {
    for (const Json& primitive : primitives.arrayItems()) {
      Primitive item;
      item.type = primitive.at("type").asString();
      const Json& points = primitive.at("points");
      if (points.isArray()) {
        for (const Json& point : points.arrayItems()) {
          item.points.push_back({point.at("x").asNumber(), point.at("y").asNumber()});
        }
      }
      result.primitives.push_back(std::move(item));
    }
  }
  return result;
}

bool sameGeometry(const std::vector<Segment>& a, const std::vector<Segment>& b) {
  if (a.size() != b.size()) {
    return false;
  }
  for (size_t i = 0; i < a.size(); ++i) {
    if (a[i].x1 != b[i].x1 || a[i].y1 != b[i].y1 || a[i].x2 != b[i].x2 || a[i].y2 != b[i].y2) {
      return false;
    }
  }
  return true;
}

}  // namespace rghw
