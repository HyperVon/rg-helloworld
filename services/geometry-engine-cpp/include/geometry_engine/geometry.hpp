#ifndef RGHELLO_GEOMETRY_ENGINE_GEOMETRY_HPP_
#define RGHELLO_GEOMETRY_ENGINE_GEOMETRY_HPP_

#include <cstddef>
#include <string>
#include <vector>

#include "geometry_engine/json.hpp"

namespace rghw {

struct Point {
  double x;
  double y;
};

struct Segment {
  double x1;
  double y1;
  double x2;
  double y2;
};

struct Primitive {
  std::string type;
  std::vector<Point> points;
};

struct BlueprintGlyph {
  std::string glyphInstanceId;
  int position = 0;
  std::string kind;  // DRAWABLE | GAP
  double advanceWidth = 0.0;
  std::vector<Primitive> primitives;
};

struct GeometryStats {
  double xMin = 0.0;
  double yMin = 0.0;
  double xMax = 0.0;
  double yMax = 0.0;
  size_t segmentCount = 0;
  double totalLength = 0.0;
  size_t intersectionCount = 0;
  std::string geometrySha256;
};

// Expands one primitive into explicit segments. POLYLINE yields consecutive
// point segments; ARC (points = start, end, center) is approximated with
// `subdivisions` line segments counter-clockwise around the center; POINT
// yields nothing.
std::vector<Segment> expandPrimitive(const Primitive& primitive, int arcSubdivisions);

// Removes segments with non-finite coordinates, drops zero-length segments,
// and merges exactly collinear adjacent segments when merging preserves the
// shape. Deterministic and order-preserving.
std::vector<Segment> cleanSegments(const std::vector<Segment>& input);

// Computes bounding box, segment count, total path length, pairwise
// intersection count (proper crossings only), and the canonical SHA-256 of
// the segments.
GeometryStats computeStats(const std::vector<Segment>& segments);

// Canonical JSON document for a drawable geometry artifact.
Json drawableGeometryJson(const std::vector<Segment>& segments, const GeometryStats& stats,
                          double advanceWidth);

// Canonical JSON document for a gap geometry artifact (stage 2 layout record).
Json gapGeometryJson(double advanceWidth, double leftBearing, double rightBearing);

// Parses the data payload of a glyph-blueprint-produced CloudEvent.
BlueprintGlyph parseBlueprintGlyph(const Json& data);

// True when two primitives produce the same expanded, cleaned segments.
bool sameGeometry(const std::vector<Segment>& a, const std::vector<Segment>& b);

}  // namespace rghw

#endif  // RGHELLO_GEOMETRY_ENGINE_GEOMETRY_HPP_
