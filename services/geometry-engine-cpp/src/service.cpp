#include "geometry_engine/service.hpp"

#include <cctype>
#include <cstdint>
#include <stdexcept>
#include <utility>

#include "geometry_engine/geometry.hpp"
#include "geometry_engine/json.hpp"
#include "geometry_engine/sha256.hpp"

namespace rghw {

namespace {

constexpr char kSource[] = "geometry-engine";
constexpr char kStepName[] = "expand-geometry";
constexpr char kStepVersion[] = "1.0.0";

std::string lowerHex(const std::string& value) {
  std::string out = value;
  for (char& c : out) {
    c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
  }
  return out;
}

// Deterministic UUID from the operation ID: first 16 bytes of the SHA-256,
// with RFC 4122 version 4 and variant 10 bits set.
std::string uuidFromOperationId(const std::string& operationId) {
  std::string hex = lowerHex(operationId);
  if (hex.size() < 32) {
    throw std::runtime_error("operation id too short for UUID derivation");
  }
  auto hexVal = [](char c) -> uint8_t {
    if (c >= '0' && c <= '9') {
      return static_cast<uint8_t>(c - '0');
    }
    return static_cast<uint8_t>(c - 'a' + 10);
  };
  uint8_t bytes[16];
  for (int i = 0; i < 16; ++i) {
    bytes[i] = static_cast<uint8_t>((hexVal(hex[2 * i]) << 4) | hexVal(hex[2 * i + 1]));
  }
  bytes[6] = static_cast<uint8_t>((bytes[6] & 0x0F) | 0x40);
  bytes[8] = static_cast<uint8_t>((bytes[8] & 0x3F) | 0x80);
  char buffer[37];
  std::snprintf(buffer, sizeof(buffer),
                "%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x", bytes[0],
                bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8],
                bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]);
  return std::string(buffer);
}

Json segmentJson(const Segment& segment) {
  Json item = Json::object();
  item.objectItems()["x1"] = Json::number(segment.x1);
  item.objectItems()["y1"] = Json::number(segment.y1);
  item.objectItems()["x2"] = Json::number(segment.x2);
  item.objectItems()["y2"] = Json::number(segment.y2);
  return item;
}

Json geometryEventGeometry(const BlueprintGlyph& glyph, const std::vector<Segment>& segments,
                           const GeometryStats& stats) {
  Json geometry = Json::object();
  if (glyph.kind == "GAP") {
    geometry.objectItems()["kind"] = Json::str("GAP_GEOMETRY");
    geometry.objectItems()["segments"] = Json::array();
    Json bbox = Json::object();
    bbox.objectItems()["xMin"] = Json::number(0.0);
    bbox.objectItems()["yMin"] = Json::number(0.0);
    bbox.objectItems()["xMax"] = Json::number(0.0);
    bbox.objectItems()["yMax"] = Json::number(0.0);
    geometry.objectItems()["boundingBox"] = std::move(bbox);
    geometry.objectItems()["advanceWidth"] = Json::number(glyph.advanceWidth);
    geometry.objectItems()["totalLength"] = Json::number(0.0);
    geometry.objectItems()["segmentCount"] = Json::number(0.0);
    geometry.objectItems()["geometrySha256"] = Json::str(stats.geometrySha256);
    return geometry;
  }
  geometry.objectItems()["kind"] = Json::str("DRAWABLE_GEOMETRY");
  Json segmentArray = Json::array();
  for (const Segment& segment : segments) {
    segmentArray.arrayItems().push_back(segmentJson(segment));
  }
  geometry.objectItems()["segments"] = std::move(segmentArray);
  Json bbox = Json::object();
  bbox.objectItems()["xMin"] = Json::number(stats.xMin);
  bbox.objectItems()["yMin"] = Json::number(stats.yMin);
  bbox.objectItems()["xMax"] = Json::number(stats.xMax);
  bbox.objectItems()["yMax"] = Json::number(stats.yMax);
  geometry.objectItems()["boundingBox"] = std::move(bbox);
  geometry.objectItems()["advanceWidth"] = Json::number(glyph.advanceWidth);
  geometry.objectItems()["totalLength"] = Json::number(stats.totalLength);
  geometry.objectItems()["segmentCount"] = Json::number(static_cast<double>(stats.segmentCount));
  geometry.objectItems()["geometrySha256"] = Json::str(stats.geometrySha256);
  return geometry;
}

std::string glyphDirectory(const std::string& runId, int position,
                           const std::string& glyphInstanceId) {
  return "runs/" + runId + "/glyphs/" + std::to_string(position) + "-" + glyphInstanceId;
}

}  // namespace

GeometryOutcome processBlueprint(const std::string& inputEventJson, const GeometryConfig& config) {
  Json event = Json::parse(inputEventJson);
  if (!event.isObject()) {
    throw std::runtime_error("blueprint event is not a JSON object");
  }
  const Json& data = event.at("data");
  if (!data.isObject()) {
    throw std::runtime_error("blueprint event has no data object");
  }
  BlueprintGlyph glyph = parseBlueprintGlyph(data);
  std::string runId = data.at("runId").asString();
  std::string stepId = data.at("stepId").asString();
  int attempt = static_cast<int>(data.at("attempt").asInt64());

  std::string inputArtifactHash = sha256Hex(data.serialize());
  std::string operationId = sha256Hex(runId + kStepName + glyph.glyphInstanceId +
                                      std::to_string(attempt) + inputArtifactHash);

  GeometryOutcome outcome;
  std::string directory = glyphDirectory(runId, glyph.position, glyph.glyphInstanceId);
  outcome.blueprintArtifactKey = directory + "/blueprint.json";
  outcome.blueprintArtifactJson = data.serialize();
  outcome.geometryArtifactKey =
      directory + "/geometry-attempt-" + std::to_string(attempt) + "-" + operationId + ".json";

  std::vector<Segment> segments;
  GeometryStats stats;
  if (glyph.kind == "GAP") {
    Json gap = gapGeometryJson(glyph.advanceWidth, 0.0, 0.0);
    outcome.geometryArtifactJson = gap.serialize();
    stats.geometrySha256 = sha256Hex(outcome.geometryArtifactJson);
  } else {
    for (const Primitive& primitive : glyph.primitives) {
      std::vector<Segment> expanded = expandPrimitive(primitive, config.arcSubdivisions);
      segments.insert(segments.end(), expanded.begin(), expanded.end());
    }
    segments = cleanSegments(segments);
    stats = computeStats(segments);
    Json artifact = drawableGeometryJson(segments, stats, glyph.advanceWidth);
    outcome.geometryArtifactJson = artifact.serialize();
    stats.geometrySha256 = sha256Hex(outcome.geometryArtifactJson);
  }

  Json output = Json::object();
  output.objectItems()["specversion"] = Json::str("1.0");
  output.objectItems()["id"] = Json::str(uuidFromOperationId(operationId));
  output.objectItems()["source"] = Json::str(kSource);
  output.objectItems()["type"] = Json::str(config.outputTopic);
  output.objectItems()["subject"] = Json::str("runs/" + runId + "/glyphs/" + glyph.glyphInstanceId);
  if (event.has("time")) {
    output.objectItems()["time"] = event.at("time");
  }
  output.objectItems()["datacontenttype"] = Json::str("application/json");
  output.objectItems()["correlationid"] = Json::str(runId);
  if (event.has("id")) {
    output.objectItems()["causationid"] = event.at("id");
  }

  Json outputData = Json::object();
  outputData.objectItems()["runId"] = Json::str(runId);
  outputData.objectItems()["stepId"] = Json::str(stepId);
  outputData.objectItems()["glyphInstanceId"] = Json::str(glyph.glyphInstanceId);
  outputData.objectItems()["position"] = Json::number(static_cast<double>(glyph.position));
  outputData.objectItems()["attempt"] = Json::number(static_cast<double>(attempt));
  outputData.objectItems()["inputMaturity"] = Json::number(10.0);
  outputData.objectItems()["outputMaturity"] = Json::number(20.0);
  Json inputArtifacts = Json::array();
  inputArtifacts.arrayItems().push_back(Json::str(outcome.blueprintArtifactKey));
  outputData.objectItems()["inputArtifacts"] = std::move(inputArtifacts);
  Json outputArtifacts = Json::array();
  outputArtifacts.arrayItems().push_back(Json::str(outcome.geometryArtifactKey));
  outputData.objectItems()["outputArtifacts"] = std::move(outputArtifacts);
  Json transformation = Json::object();
  transformation.objectItems()["name"] = Json::str(kStepName);
  transformation.objectItems()["version"] = Json::str(kStepVersion);
  outputData.objectItems()["transformation"] = std::move(transformation);
  outputData.objectItems()["geometry"] = geometryEventGeometry(glyph, segments, stats);
  output.objectItems()["data"] = std::move(outputData);

  outcome.outputEventJson = output.serialize();
  return outcome;
}

bool WorkerLoop::processOne() {
  std::string message;
  if (!transport_.poll(&message)) {
    return false;
  }
  GeometryOutcome outcome = processBlueprint(message, config_);
  if (!store_.putObject(config_.minioBucket, outcome.blueprintArtifactKey,
                        outcome.blueprintArtifactJson)) {
    throw std::runtime_error("failed to store blueprint artifact: " + outcome.blueprintArtifactKey);
  }
  if (!store_.putObject(config_.minioBucket, outcome.geometryArtifactKey,
                        outcome.geometryArtifactJson)) {
    throw std::runtime_error("failed to store geometry artifact: " + outcome.geometryArtifactKey);
  }
  Json outputEvent = Json::parse(outcome.outputEventJson);
  const Json& data = outputEvent.at("data");
  std::string key = data.at("runId").asString() + ":" + data.at("glyphInstanceId").asString();
  if (!transport_.produce(config_.outputTopic, key, outcome.outputEventJson)) {
    throw std::runtime_error("failed to publish geometry event");
  }
  return true;
}

}  // namespace rghw
