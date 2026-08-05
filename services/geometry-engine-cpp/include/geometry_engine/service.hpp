#ifndef RGHELLO_GEOMETRY_ENGINE_SERVICE_HPP_
#define RGHELLO_GEOMETRY_ENGINE_SERVICE_HPP_

#include <string>
#include <vector>

namespace rghello {

struct GeometryConfig {
  std::string outputTopic = "rg.geometry-expanded.v1";
  int arcSubdivisions = 12;
  std::string minioBucket = "rube-goldberg-artifacts";
};

struct GeometryOutcome {
  std::string outputEventJson;
  std::string blueprintArtifactKey;
  std::string blueprintArtifactJson;
  std::string geometryArtifactKey;
  std::string geometryArtifactJson;
};

// Pure pipeline step: expands one glyph-blueprint CloudEvent into the
// geometry artifacts and the GeometryExpanded CloudEvent. Deterministic for
// a given input. Throws std::runtime_error on invalid input.
GeometryOutcome processBlueprint(const std::string& inputEventJson, const GeometryConfig& config);

// Transport abstraction over Kafka for testability.
struct KafkaTransport {
  virtual ~KafkaTransport() = default;
  virtual bool poll(std::string* message) = 0;
  virtual bool produce(const std::string& topic, const std::string& key,
                       const std::string& value) = 0;
};

// Object-store abstraction over MinIO for testability.
struct ObjectStore {
  virtual ~ObjectStore() = default;
  virtual bool putObject(const std::string& bucket, const std::string& key, const std::string& body,
                         std::string* etagOut = nullptr) = 0;
};

// Consume loop: poll blueprint events, expand, store artifacts, publish the
// geometry event. Idempotent: identical events produce identical artifacts
// and events (deterministic operation IDs).
class WorkerLoop {
 public:
  WorkerLoop(KafkaTransport& transport, ObjectStore& store, GeometryConfig config)
      : transport_(transport), store_(store), config_(std::move(config)) {}

  // Processes one message; returns false when the poll timed out.
  bool processOne();

 private:
  KafkaTransport& transport_;
  ObjectStore& store_;
  GeometryConfig config_;
};

}  // namespace rghello

#endif  // RGHELLO_GEOMETRY_ENGINE_SERVICE_HPP_
