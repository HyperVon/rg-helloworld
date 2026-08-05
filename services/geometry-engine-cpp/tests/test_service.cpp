#include <iostream>
#include <string>
#include <utility>
#include <vector>

#include "geometry_engine/json.hpp"
#include "geometry_engine/service.hpp"
#include "geometry_engine/sha256.hpp"

namespace {

int failures = 0;

void expect(bool condition, const std::string& message) {
  if (!condition) {
    std::cerr << "FAIL: " << message << '\n';
    ++failures;
  }
}

void expectEq(const std::string& actual, const std::string& expected, const std::string& message) {
  if (actual != expected) {
    std::cerr << "FAIL: " << message << "\n  expected: " << expected << "\n  actual:   " << actual
              << '\n';
    ++failures;
  }
}

void expectThrows(const std::string& input) {
  try {
    rghello::processBlueprint(input, {});
    std::cerr << "FAIL: expected processing error\n";
    ++failures;
  } catch (const std::exception&) {
  }
}

rghello::Json point(double x, double y) {
  rghello::Json p = rghello::Json::object();
  p.objectItems()["x"] = rghello::Json::number(x);
  p.objectItems()["y"] = rghello::Json::number(y);
  return p;
}

rghello::Json primitive(const std::string& type, std::vector<rghello::Json> points) {
  rghello::Json p = rghello::Json::object();
  p.objectItems()["type"] = rghello::Json::str(type);
  rghello::Json array = rghello::Json::array();
  array.arrayItems() = std::move(points);
  p.objectItems()["points"] = std::move(array);
  return p;
}

// Builds a glyph-blueprint CloudEvent with a single glyph.
std::string blueprintEvent(const std::string& kind, int position, const std::string& glyphId,
                           double advanceWidth, std::vector<rghello::Json> primitives) {
  rghello::Json event = rghello::Json::object();
  event.objectItems()["specversion"] = rghello::Json::str("1.0");
  event.objectItems()["id"] = rghello::Json::str("11111111-1111-4111-8111-111111111111");
  event.objectItems()["source"] = rghello::Json::str("run-orchestrator");
  event.objectItems()["type"] = rghello::Json::str("rg.glyph-blueprints.v1");
  event.objectItems()["subject"] = rghello::Json::str("runs/22222222-2222-4222-8222-222222222222");
  event.objectItems()["time"] = rghello::Json::str("2026-08-05T00:00:00.000Z");
  event.objectItems()["datacontenttype"] = rghello::Json::str("application/json");
  event.objectItems()["correlationid"] = rghello::Json::str("22222222-2222-4222-8222-222222222222");

  rghello::Json data = rghello::Json::object();
  data.objectItems()["runId"] = rghello::Json::str("22222222-2222-4222-8222-222222222222");
  data.objectItems()["planId"] = rghello::Json::str("33333333-3333-4333-8333-333333333333");
  data.objectItems()["stepId"] = rghello::Json::str("44444444-4444-4444-8444-444444444444");
  data.objectItems()["attempt"] = rghello::Json::number(1.0);
  data.objectItems()["inputArtifacts"] = rghello::Json::array();
  data.objectItems()["outputArtifacts"] = rghello::Json::array();
  rghello::Json transformation = rghello::Json::object();
  transformation.objectItems()["name"] = rghello::Json::str("plan-glyphs");
  transformation.objectItems()["version"] = rghello::Json::str("1.0.0");
  data.objectItems()["transformation"] = std::move(transformation);
  rghello::Json glyph = rghello::Json::object();
  glyph.objectItems()["glyphInstanceId"] = rghello::Json::str(glyphId);
  glyph.objectItems()["position"] = rghello::Json::number(static_cast<double>(position));
  glyph.objectItems()["kind"] = rghello::Json::str(kind);
  glyph.objectItems()["advanceWidth"] = rghello::Json::number(advanceWidth);
  rghello::Json primitivesArray = rghello::Json::array();
  primitivesArray.arrayItems() = std::move(primitives);
  glyph.objectItems()["primitives"] = std::move(primitivesArray);
  rghello::Json glyphs = rghello::Json::array();
  glyphs.arrayItems().push_back(std::move(glyph));
  data.objectItems()["glyphs"] = std::move(glyphs);
  event.objectItems()["data"] = std::move(data);
  return event.serialize();
}

bool isUuid(const std::string& value) {
  if (value.size() != 36) {
    return false;
  }
  for (size_t i = 0; i < value.size(); ++i) {
    char c = value[i];
    bool hex = (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
    if (i == 8 || i == 13 || i == 18 || i == 23) {
      if (c != '-') {
        return false;
      }
    } else if (!hex) {
      return false;
    }
  }
  return true;
}

// Fake transport and store for WorkerLoop tests.
class FakeTransport : public rghello::KafkaTransport {
 public:
  std::vector<std::string> messages;
  std::vector<std::string> publishedTopics;
  std::vector<std::string> publishedKeys;
  std::vector<std::string> publishedValues;
  size_t pollIndex = 0;
  bool produceResult = true;

  bool poll(std::string* message) override {
    if (pollIndex >= messages.size()) {
      return false;
    }
    *message = messages[pollIndex++];
    return true;
  }

  bool produce(const std::string& topic, const std::string& key,
               const std::string& value) override {
    publishedTopics.push_back(topic);
    publishedKeys.push_back(key);
    publishedValues.push_back(value);
    return produceResult;
  }
};

class FakeStore : public rghello::ObjectStore {
 public:
  std::vector<std::string> keys;
  std::vector<std::string> bodies;
  bool putResult = true;

  bool putObject(const std::string& bucket, const std::string& key, const std::string& body,
                 std::string* etagOut = nullptr) override {
    keys.push_back(key);
    bodies.push_back(body);
    return putResult;
  }
};

}  // namespace

int main() {
  const std::string runId = "22222222-2222-4222-8222-222222222222";
  const std::string glyphId = "55555555-5555-4555-8555-555555555555";
  const std::string stepId = "44444444-4444-4444-8444-444444444444";
  const std::string inputId = "11111111-1111-4111-8111-111111111111";

  // Drawable glyph: an 'H'-like shape made of three polylines.
  std::string input = blueprintEvent("DRAWABLE", 0, glyphId, 1.0,
                                     {primitive("POLYLINE", {point(0.1, 0.0), point(0.1, 1.0)}),
                                      primitive("POLYLINE", {point(0.9, 0.0), point(0.9, 1.0)}),
                                      primitive("POLYLINE", {point(0.1, 0.5), point(0.9, 0.5)})});

  rghello::GeometryOutcome outcome = rghello::processBlueprint(input, {});
  rghello::Json event = rghello::Json::parse(outcome.outputEventJson);
  rghello::Json data = event.at("data");

  expectEq(event.at("specversion").asString(), "1.0", "envelope specversion");
  expectEq(event.at("source").asString(), "geometry-engine", "envelope source");
  expectEq(event.at("type").asString(), "rg.geometry-expanded.v1", "envelope type");
  expectEq(event.at("subject").asString(), "runs/" + runId + "/glyphs/" + glyphId, "subject");
  expectEq(event.at("time").asString(), "2026-08-05T00:00:00.000Z", "time inherited from input");
  expectEq(event.at("correlationid").asString(), runId, "correlation id");
  expectEq(event.at("causationid").asString(), inputId, "causation id");
  expect(isUuid(event.at("id").asString()), "event id is a UUID");

  expectEq(data.at("runId").asString(), runId, "data run id");
  expectEq(data.at("stepId").asString(), stepId, "data step id");
  expectEq(data.at("glyphInstanceId").asString(), glyphId, "data glyph id");
  expect(data.at("position").asInt64() == 0, "data position");
  expect(data.at("attempt").asInt64() == 1, "data attempt");
  expect(data.at("inputMaturity").asInt64() == 10, "input maturity 10");
  expect(data.at("outputMaturity").asInt64() == 20, "output maturity 20");
  expectEq(data.at("transformation").at("name").asString(), "expand-geometry",
           "transformation name");
  expectEq(data.at("transformation").at("version").asString(), "1.0.0", "transformation version");

  rghello::Json geometry = data.at("geometry");
  expectEq(geometry.at("kind").asString(), "DRAWABLE_GEOMETRY", "drawable geometry kind");
  expect(geometry.at("segments").arrayItems().size() == 3, "three segments for H");
  expect(geometry.at("segmentCount").asInt64() == 3, "segment count field");
  expectEq(geometry.at("boundingBox").at("xMin").serialize(), "0.1", "bbox xMin");
  expectEq(geometry.at("boundingBox").at("yMax").serialize(), "1", "bbox yMax");
  expect(geometry.at("totalLength").asNumber() > 2.0, "total length positive");

  // Artifact keys: deterministic directory + operation ID in the geometry key.
  std::string directory = "runs/" + runId + "/glyphs/0-" + glyphId;
  std::string operationId =
      rghello::sha256Hex(runId + "expand-geometry" + glyphId + "1" +
                         rghello::sha256Hex(rghello::Json::parse(input).at("data").serialize()));
  expectEq(outcome.blueprintArtifactKey, directory + "/blueprint.json", "blueprint artifact key");
  expectEq(outcome.geometryArtifactKey, directory + "/geometry-attempt-1-" + operationId + ".json",
           "geometry artifact key embeds the operation id");
  expectEq(data.at("inputArtifacts").arrayItems()[0].asString(), outcome.blueprintArtifactKey,
           "input artifact reference");
  expectEq(data.at("outputArtifacts").arrayItems()[0].asString(), outcome.geometryArtifactKey,
           "output artifact reference");
  expectEq(outcome.blueprintArtifactJson, rghello::Json::parse(input).at("data").serialize(),
           "blueprint snapshot is the data payload");
  expectEq(geometry.at("geometrySha256").asString(),
           rghello::sha256Hex(outcome.geometryArtifactJson), "geometry checksum matches artifact");

  // Determinism: identical input yields byte-identical output.
  expectEq(rghello::processBlueprint(input, {}).outputEventJson, outcome.outputEventJson,
           "geometry processing is deterministic");

  // Gap glyphs produce GAP_GEOMETRY layout records, not empty drawables.
  std::string gapInput = blueprintEvent("GAP", 5, "66666666-6666-4666-8666-666666666666", 0.6, {});

  rghello::GeometryOutcome gapOutcome = rghello::processBlueprint(gapInput, {});
  rghello::Json gapData = rghello::Json::parse(gapOutcome.outputEventJson).at("data");
  rghello::Json gapGeometry = gapData.at("geometry");
  expectEq(gapGeometry.at("kind").asString(), "GAP_GEOMETRY", "gap geometry kind");
  expect(gapGeometry.at("segments").arrayItems().empty(), "gap has no segments");
  expectEq(gapGeometry.at("advanceWidth").serialize(), "0.6", "gap advance width preserved");
  expect(gapGeometry.at("totalLength").asNumber() == 0.0, "gap total length zero");
  expect(gapGeometry.at("segmentCount").asInt64() == 0, "gap segment count zero");
  expectEq(gapOutcome.geometryArtifactJson,
           "{\"advanceWidth\":0.6,\"kind\":\"GAP_GEOMETRY\",\"leftBearing\":0,\"rightBearing\":0}",
           "gap artifact layout record");
  expectEq(gapGeometry.at("geometrySha256").asString(),
           rghello::sha256Hex(gapOutcome.geometryArtifactJson), "gap checksum matches artifact");

  // Invalid inputs are rejected.
  expectThrows("not json");
  expectThrows("[]");
  expectThrows("{\"data\":{}}");
  expectThrows("{\"data\":{\"glyphs\":[]}}");
  expectThrows(blueprintEvent("DRAWABLE", 0, glyphId, 1.0, {primitive("ARC", {point(0.0, 0.0)})}));

  // Worker loop: full poll -> store -> publish flow.

  FakeTransport transport;
  transport.messages = {input};
  FakeStore store;
  rghello::WorkerLoop loop(transport, store, {});
  expect(loop.processOne(), "first message processed");
  expect(!loop.processOne(), "poll timeout returns false");
  expect(store.keys.size() == 2, "two artifacts stored");
  expectEq(store.keys[0], outcome.blueprintArtifactKey, "blueprint stored first");
  expectEq(store.keys[1], outcome.geometryArtifactKey, "geometry stored second");
  expect(transport.publishedTopics.size() == 1, "one event published");
  expectEq(transport.publishedTopics[0], "rg.geometry-expanded.v1", "output topic");
  expectEq(transport.publishedKeys[0], runId + ":" + glyphId,
           "partition key runId:glyphInstanceId");
  expectEq(transport.publishedValues[0], outcome.outputEventJson, "published event matches");

  // Store failure surfaces as an exception.
  FakeTransport failingTransport;
  failingTransport.messages = {input};
  FakeStore failingStore;
  failingStore.putResult = false;
  rghello::WorkerLoop failingLoop(failingTransport, failingStore, {});
  try {
    failingLoop.processOne();
    std::cerr << "FAIL: store failure should throw\n";
    ++failures;
  } catch (const std::runtime_error&) {
  }

  // Produce failure surfaces as an exception.
  FakeTransport produceFailingTransport;
  produceFailingTransport.messages = {input};
  produceFailingTransport.produceResult = false;
  FakeStore okStore;
  rghello::WorkerLoop produceFailingLoop(produceFailingTransport, okStore, {});
  try {
    produceFailingLoop.processOne();
    std::cerr << "FAIL: produce failure should throw\n";
    ++failures;
  } catch (const std::runtime_error&) {
  }

  if (failures == 0) {
    std::cout << "service tests passed\n";
    return 0;
  }
  std::cerr << failures << " service test(s) failed\n";
  return 1;
}
