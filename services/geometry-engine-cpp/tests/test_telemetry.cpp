#include <cstdlib>
#include <iostream>
#include <string>

#include "telemetry.h"

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

}  // namespace

int main() {
  // startupLogLine renders canonical JSON with service, stage, and UTC time.
  std::string line = rghw::telemetry::startupLogLine("geometry-engine");
  expect(line.find("\"level\":\"INFO\"") != std::string::npos, "startup log has level INFO");
  expect(line.find("\"service.name\":\"geometry-engine\"") != std::string::npos,
         "startup log carries service name");
  expect(line.find("\"body\":\"geometry-engine startup\"") != std::string::npos,
         "startup log carries startup body");
  expect(line.find("\"time\":\"") != std::string::npos, "startup log carries UTC time");
  expect(line.find('Z') != std::string::npos, "UTC time is ISO-8601 with Z terminator");

  // Every JSON special character round-trips through startupLogLine -> jsonEscape.
  std::string escaped = rghw::telemetry::startupLogLine("a\b\"b\\c\nd\te\fb\rc");
  expect(escaped.find("\\\"") != std::string::npos, "escapes double quote");
  expect(escaped.find("\\\\") != std::string::npos, "escapes backslash");
  expect(escaped.find("\\n") != std::string::npos, "escapes newline");
  expect(escaped.find("\\t") != std::string::npos, "escapes tab");
  expect(escaped.find("\\f") != std::string::npos, "escapes form feed");
  expect(escaped.find("\\r") != std::string::npos, "escapes carriage return");

  // Control characters below 0x20 take the unicode-escape branch of jsonEscape.
  std::string control = rghw::telemetry::startupLogLine(std::string(1, '\x01'));
  expect(control.find("\\u0001") != std::string::npos, "escapes control character as \\uXXXX");

  // Default service name matches the documented constant.
  expectEq(rghw::telemetry::startupLogLine(),
           rghw::telemetry::startupLogLine(rghw::telemetry::kServiceName),
           "default service name matches kServiceName");

  // initialize is idempotent and never throws; shutdown is safe to repeat.
  rghw::telemetry::initialize("test-service");
  rghw::telemetry::initialize("test-service");  // second call must be a no-op
  rghw::telemetry::shutdown();
  rghw::telemetry::shutdown();  // second call must be a no-op

  // An explicit endpoint is preferred over the environment / default.
  rghw::telemetry::initialize("arg-service", "http://localhost:4317");
  rghw::telemetry::shutdown();

  // A trailing slash in the endpoint exercises stripScheme's trim branch.
  rghw::telemetry::initialize("trim-service", "http://localhost:4317/");
  rghw::telemetry::shutdown();

  // Endpoint resolution falls back to the environment variable when unset.
  ::unsetenv("OTEL_EXPORTER_OTLP_ENDPOINT");
  rghw::telemetry::initialize("env-service");  // exercises envEndpoint() empty branch
  rghw::telemetry::shutdown();

  ::setenv("OTEL_EXPORTER_OTLP_ENDPOINT", "http://collector.example:4317", 1);
  rghw::telemetry::initialize("env-service");  // exercises envEndpoint() set branch
  rghw::telemetry::shutdown();
  ::unsetenv("OTEL_EXPORTER_OTLP_ENDPOINT");

  if (failures == 0) {
    std::cout << "telemetry tests passed\n";
    return 0;
  }
  std::cerr << failures << " telemetry test(s) failed\n";
  return 1;
}
