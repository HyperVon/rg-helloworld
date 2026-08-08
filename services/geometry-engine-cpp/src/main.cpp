#include <chrono>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <string>
#include <thread>
#include <vector>

#include "geometry_engine/kafka.hpp"
#include "geometry_engine/s3.hpp"
#include "geometry_engine/service.hpp"
#include "geometry_engine/version.hpp"
#include "telemetry.h"

namespace {

constexpr char kInputTopicDefault[] = "rg.glyph-blueprints.v1";

std::string envOr(const char* name, const std::string& fallback) {
  const char* value = std::getenv(name);
  return (value == nullptr || *value == '\0') ? fallback : std::string(value);
}

int envIntOr(const char* name, int fallback) {
  const char* value = std::getenv(name);
  if (value == nullptr || *value == '\0') {
    return fallback;
  }
  return std::atoi(value);
}

int runOnce(const std::string& artifactsDir) {
  std::string input((std::istreambuf_iterator<char>(std::cin)), std::istreambuf_iterator<char>());
  rghw::GeometryConfig config;
  config.outputTopic = envOr("GEOMETRY_OUTPUT_TOPIC", config.outputTopic);
  config.arcSubdivisions = envIntOr("GEOMETRY_ARC_SUBDIVISIONS", config.arcSubdivisions);
  config.minioBucket = envOr("MINIO_BUCKET", config.minioBucket);
  rghw::GeometryOutcome outcome = rghw::processBlueprint(input, config);
  if (!artifactsDir.empty()) {
    std::filesystem::create_directories(artifactsDir);
    auto write = [&](const std::string& key, const std::string& body) {
      std::string name = key.substr(key.find_last_of('/') + 1);
      std::ofstream out(artifactsDir + "/" + name);
      out << body;
    };
    write(outcome.blueprintArtifactKey, outcome.blueprintArtifactJson);
    write(outcome.geometryArtifactKey, outcome.geometryArtifactJson);
  }
  std::cout << outcome.outputEventJson << '\n';
  return 0;
}

int runWorker() {
  std::string bootstrap = envOr("KAFKA_BOOTSTRAP", "localhost:9092");
  std::string groupId = envOr("KAFKA_GROUP_ID", "geometry-engine");
  std::string inputTopic = envOr("GEOMETRY_INPUT_TOPIC", kInputTopicDefault);
  int pollTimeoutMs = envIntOr("KAFKA_POLL_TIMEOUT_MS", 1000);

  rghw::KafkaClient kafka(bootstrap, groupId, pollTimeoutMs);
  kafka.subscribe({inputTopic});

  rghw::S3Client s3(envOr("MINIO_ENDPOINT", "http://localhost:9000"),
                    envOr("MINIO_ACCESS_KEY", "minioadmin"),
                    envOr("MINIO_SECRET_KEY", "minioadmin"), 5000);

  rghw::GeometryConfig config;
  config.outputTopic = envOr("GEOMETRY_OUTPUT_TOPIC", config.outputTopic);
  config.arcSubdivisions = envIntOr("GEOMETRY_ARC_SUBDIVISIONS", config.arcSubdivisions);
  config.minioBucket = envOr("MINIO_BUCKET", config.minioBucket);

  rghw::WorkerLoop loop(kafka, s3, config);
  while (true) {
    try {
      if (loop.processOne()) {
        kafka.commit();
      }
    } catch (const std::exception& error) {
      // The uncommitted offset is redelivered after a restart, so a failed
      // message is never lost. Back off briefly to avoid a hot error loop.
      std::cerr << "geometry-engine: " << error.what() << '\n';
      std::this_thread::sleep_for(std::chrono::seconds(1));
    }
  }
}

}  // namespace

int main(int argc, char** argv) {
  std::vector<std::string> args(argv + 1, argv + argc);
  if (!args.empty() && args[0] == "version") {
    std::cout << geometry_engine::kBanner << '\n';
    return 0;
  }
  rghw::telemetry::initialize();
  std::atexit(&rghw::telemetry::shutdown);
  if (!args.empty() && args[0] == "--once") {
    std::string artifactsDir;
    for (size_t i = 1; i < args.size(); ++i) {
      if (args[i] == "--artifacts-dir" && i + 1 < args.size()) {
        artifactsDir = args[++i];
      }
    }
    return runOnce(artifactsDir);
  }
  return runWorker();
}
