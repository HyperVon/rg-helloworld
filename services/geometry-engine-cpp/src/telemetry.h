#ifndef RGHELLO_GEOMETRY_ENGINE_TELEMETRY_H
#define RGHELLO_GEOMETRY_ENGINE_TELEMETRY_H

#include <string>

namespace rghw {
namespace telemetry {

// OTLP/gRPC collector endpoint used when OTEL_EXPORTER_OTLP_ENDPOINT is unset.
// Matches the in-cluster collector address used by the other rghw services.
inline constexpr const char* kDefaultEndpoint = "http://otel-collector.rube-goldberg:4317";

// service.name reported on every signal emitted by this service.
inline constexpr const char* kServiceName = "geometry-engine";

// Best-effort telemetry bootstrap.
//
// Builds the OTLP/gRPC trace and log exporters against `otlpEndpoint` (or the
// OTEL_EXPORTER_OTLP_ENDPOINT env var, or kDefaultEndpoint), installs a span
// processor and a log processor with resource service.name set to
// `serviceName`, and emits one startup log record.
//
// The call is idempotent: a second call is a no-op. It never blocks startup on
// a network export and never throws; if the OpenTelemetry C++ SDK is not
// linked (offline-safe default build) a structured startup log line is still
// emitted to stderr and the service runs without export.
//
// Integrity: emitted records carry only service/stage/status metadata. They
// never include the requested plaintext, expected characters, glyph geometry,
// SVG, or image bytes.
void initialize(const std::string& serviceName = kServiceName,
                const std::string& otlpEndpoint = "") noexcept;

// Flushes any buffered spans/log records to the collector and unregisters the
// global providers. Safe to call repeatedly; a no-op when telemetry was never
// initialized or when running on the dependency-free fallback path. Never
// blocks on network I/O.
void shutdown() noexcept;

// Renders the single structured startup log line as canonical JSON. Exposed
// for tests and for the fallback (non-OTel) emission path.
std::string startupLogLine(const std::string& serviceName = kServiceName);

}  // namespace telemetry
}  // namespace rghw

#endif  // RGHELLO_GEOMETRY_ENGINE_TELEMETRY_H
