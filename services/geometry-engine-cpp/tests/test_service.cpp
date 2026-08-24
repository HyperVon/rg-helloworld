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
    rghw::processBlueprint(input, {});
    std::cerr << "FAIL: expected processing error\n";
    ++failures;
  } catch (const std::exception&) {
  }
}

rghw::Json point(double x, double y) {
  rghw::Json p = rghw::Json::object();
  p.objectItems()["x"] = rghw::Json::number(x);
  p.objectItems()["y"] = rghw::Json::number(y);
  return p;
}

rghw::Json primitive(const std::string& type, std::vector<rghw::Json> points) {
  rghw::Json p = rghw::Json::object();
  p.objectItems()["type"] = rghw::Json::str(type);
  rghw::Json array = rghw::Json::array();
  array.arrayItems() = std::move(points);
  p.objectItems()["points"] = std::move(array);
  return p;
}

// Builds a glyph-blueprint CloudEvent with a single glyph.
std::string blueprintEvent(const std::string& kind, int position, const std::string& glyphId,
                           double advanceWidth, std::vector<rghw::Json> primitives) {
  rghw::Json event = rghw::Json::object();
  event.objectItems()["specversion"] = rghw::Json::str("1.0");
  event.objectItems()["id"] = rghw::Json::str("11111111-1111-4111-8111-111111111111");
  event.objectItems()["source"] = rghw::Json::str("run-orchestrator");
  event.objectItems()["type"] = rghw::Json::str("rg.glyph-blueprints.v1");
  event.objectItems()["subject"] = rghw::Json::str("runs/22222222-2222-4222-8222-222222222222");
  event.objectItems()["time"] = rghw::Json::str("2026-08-05T00:00:00.000Z");
  event.objectItems()["datacontenttype"] = rghw::Json::str("application/json");
  event.objectItems()["correlationid"] = rghw::Json::str("22222222-2222-4222-8222-222222222222");

  rghw::Json data = rghw::Json::object();
  data.objectItems()["runId"] = rghw::Json::str("22222222-2222-4222-8222-222222222222");
  data.objectItems()["planId"] = rghw::Json::str("33333333-3333-4333-8333-333333333333");
  data.objectItems()["stepId"] = rghw::Json::str("44444444-4444-4444-8444-444444444444");
  data.objectItems()["attempt"] = rghw::Json::number(1.0);
  data.objectItems()["inputArtifacts"] = rghw::Json::array();
  rghw::Json planOutputs = rghw::Json::array();
  planOutputs.arrayItems().push_back(
      rghw::Json::str("runs/22222222-2222-4222-8222-222222222222/plan/glyphs.json"));
  data.objectItems()["outputArtifacts"] = std::move(planOutputs);
  rghw::Json transformation = rghw::Json::object();
  transformation.objectItems()["name"] = rghw::Json::str("plan-glyphs");
  transformation.objectItems()["version"] = rghw::Json::str("1.0.0");
  data.objectItems()["transformation"] = std::move(transformation);
  rghw::Json glyph = rghw::Json::object();
  glyph.objectItems()["glyphInstanceId"] = rghw::Json::str(glyphId);
  glyph.objectItems()["position"] = rghw::Json::number(static_cast<double>(position));
  glyph.objectItems()["kind"] = rghw::Json::str(kind);
  glyph.objectItems()["advanceWidth"] = rghw::Json::number(advanceWidth);
  rghw::Json primitivesArray = rghw::Json::array();
  primitivesArray.arrayItems() = std::move(primitives);
  glyph.objectItems()["primitives"] = std::move(primitivesArray);
  rghw::Json glyphs = rghw::Json::array();
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
class FakeTransport : public rghw::KafkaTransport {
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

class FakeStore : public rghw::ObjectStore {
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

  rghw::GeometryOutcome outcome = rghw::processBlueprint(input, {});
  rghw::Json event = rghw::Json::parse(outcome.outputEventJson);
  rghw::Json data = event.at("data");

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

  rghw::Json geometry = data.at("geometry");
  expectEq(geometry.at("kind").asString(), "DRAWABLE_GEOMETRY", "drawable geometry kind");
  expect(geometry.at("segments").arrayItems().size() == 3, "three segments for H");
  expect(geometry.at("segmentCount").asInt64() == 3, "segment count field");
  expectEq(geometry.at("boundingBox").at("xMin").serialize(), "0.1", "bbox xMin");
  expectEq(geometry.at("boundingBox").at("yMax").serialize(), "1", "bbox yMax");
  expect(geometry.at("totalLength").asNumber() > 2.0, "total length positive");

  // Artifact keys: deterministic directory + operation ID in the geometry key.
  std::string directory = "runs/" + runId + "/glyphs/0-" + glyphId;
  std::string operationId =
      rghw::sha256Hex(runId + "expand-geometry" + glyphId + "1" +
                      rghw::sha256Hex(rghw::Json::parse(input).at("data").serialize()));
  expectEq(outcome.blueprintArtifactKey, directory + "/blueprint.json", "blueprint artifact key");
  expectEq(outcome.geometryArtifactKey, directory + "/geometry-attempt-1-" + operationId + ".json",
           "geometry artifact key embeds the operation id");
  expectEq(data.at("inputArtifacts").serialize(),
           rghw::Json::parse(input).at("data").at("outputArtifacts").serialize(),
           "input artifacts trace the consumed blueprint outputs");
  expectEq(data.at("outputArtifacts").arrayItems()[0].asString(), outcome.geometryArtifactKey,
           "output artifact reference");
  expectEq(outcome.blueprintArtifactJson, rghw::Json::parse(input).at("data").serialize(),
           "blueprint snapshot is the data payload");
  expectEq(geometry.at("geometrySha256").asString(), rghw::sha256Hex(outcome.geometryArtifactJson),
           "geometry checksum matches artifact");

  // Determinism: identical input yields byte-identical output.
  expectEq(rghw::processBlueprint(input, {}).outputEventJson, outcome.outputEventJson,
           "geometry processing is deterministic");

  // Gap glyphs produce GAP_GEOMETRY layout records, not empty drawables.
  std::string gapInput = blueprintEvent("GAP", 5, "66666666-6666-4666-8666-666666666666", 0.6, {});

  rghw::GeometryOutcome gapOutcome = rghw::processBlueprint(gapInput, {});
  rghw::Json gapData = rghw::Json::parse(gapOutcome.outputEventJson).at("data");
  rghw::Json gapGeometry = gapData.at("geometry");
  expectEq(gapGeometry.at("kind").asString(), "GAP_GEOMETRY", "gap geometry kind");
  expect(gapGeometry.at("segments").arrayItems().empty(), "gap has no segments");
  expectEq(gapGeometry.at("advanceWidth").serialize(), "0.6", "gap advance width preserved");
  expect(gapGeometry.at("totalLength").asNumber() == 0.0, "gap total length zero");
  expect(gapGeometry.at("segmentCount").asInt64() == 0, "gap segment count zero");
  expectEq(gapOutcome.geometryArtifactJson,
           "{\"advanceWidth\":0.6,\"kind\":\"GAP_GEOMETRY\",\"leftBearing\":0,\"rightBearing\":0}",
           "gap artifact layout record");
  expectEq(gapGeometry.at("geometrySha256").asString(),
           rghw::sha256Hex(gapOutcome.geometryArtifactJson), "gap checksum matches artifact");

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
  rghw::WorkerLoop loop(transport, store, {});
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
  rghw::WorkerLoop failingLoop(failingTransport, failingStore, {});
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
  rghw::WorkerLoop produceFailingLoop(produceFailingTransport, okStore, {});
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
