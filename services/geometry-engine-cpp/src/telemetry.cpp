#include "telemetry.h"

#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <ctime>
#include <iostream>
#include <string>
#include <thread>

#if defined(RGHW_WITH_OPENTELEMETRY)
#include <opentelemetry/exporters/otlp/otlp_grpc_exporter_factory.h>
#include <opentelemetry/exporters/otlp/otlp_grpc_exporter_options.h>
#include <opentelemetry/exporters/otlp/otlp_grpc_log_record_exporter_factory.h>
#include <opentelemetry/exporters/otlp/otlp_grpc_log_record_exporter_options.h>
#include <opentelemetry/logs/provider.h>
#include <opentelemetry/nostd/shared_ptr.h>
#include <opentelemetry/sdk/logs/batch_log_record_processor_factory.h>
#include <opentelemetry/sdk/logs/batch_log_record_processor_options.h>
#include <opentelemetry/sdk/logs/logger_provider.h>
#include <opentelemetry/sdk/logs/logger_provider_factory.h>
#include <opentelemetry/sdk/logs/processor.h>
#include <opentelemetry/sdk/resource/resource.h>
#include <opentelemetry/sdk/trace/batch_span_processor_factory.h>
#include <opentelemetry/sdk/trace/batch_span_processor_options.h>
#include <opentelemetry/sdk/trace/processor.h>
#include <opentelemetry/sdk/trace/tracer_provider.h>
#include <opentelemetry/sdk/trace/tracer_provider_factory.h>
#include <opentelemetry/trace/provider.h>

#include <memory>

#include "geometry_engine/version.hpp"
#elif defined(RGHW_WITH_CURL_OTLP)
#include <curl/curl.h>
#endif

namespace rghw {
namespace telemetry {
namespace {

[[maybe_unused]] constexpr const char* kScope = "geometry-engine";
[[maybe_unused]] constexpr const char* kStartupMessage = "geometry-engine startup";
[[maybe_unused]] constexpr int kSeverityInfo = 9;

// Tracks whether initialize() has run so it is idempotent.
bool g_started = false;

#if defined(RGHW_WITH_OPENTELEMETRY)
std::shared_ptr<opentelemetry::sdk::trace::TracerProvider> g_tracer_provider;
std::shared_ptr<opentelemetry::sdk::logs::LoggerProvider> g_logger_provider;

void initOpenTelemetry(const std::string& serviceName, const std::string& target) {
  namespace trace = opentelemetry::trace;
  namespace trace_sdk = opentelemetry::sdk::trace;
  namespace logs_sdk = opentelemetry::sdk::logs;
  namespace otlp = opentelemetry::exporter::otlp;
  namespace resource = opentelemetry::sdk::resource;

  opentelemetry::sdk::resource::ResourceAttributes attributes = {
      {"service.name", serviceName.c_str()},
      {"service.version", std::string(geometry_engine::kVersion)},
  };
  auto res = resource::Resource::Create(attributes);

  otlp::OtlpGrpcExporterOptions trace_opts;
  trace_opts.endpoint = target;
  trace_opts.timeout = std::chrono::milliseconds(5000);
  auto trace_exporter = otlp::OtlpGrpcExporterFactory::Create(trace_opts);
  trace_sdk::BatchSpanProcessorOptions bsp_opts;
  bsp_opts.schedule_delay_millis = std::chrono::milliseconds(1000);
  auto trace_processor =
      trace_sdk::BatchSpanProcessorFactory::Create(std::move(trace_exporter), bsp_opts);
  g_tracer_provider = trace_sdk::TracerProviderFactory::Create(std::move(trace_processor), res);
  trace::Provider::SetTracerProvider(
      std::shared_ptr<opentelemetry::trace::TracerProvider>(g_tracer_provider));

  otlp::OtlpGrpcLogRecordExporterOptions log_opts;
  log_opts.endpoint = target;
  log_opts.timeout = std::chrono::milliseconds(5000);
  auto log_exporter = otlp::OtlpGrpcLogRecordExporterFactory::Create(log_opts);
  logs_sdk::BatchLogRecordProcessorOptions blp_opts;
  blp_opts.schedule_delay_millis = std::chrono::milliseconds(1000);
  auto log_processor =
      logs_sdk::BatchLogRecordProcessorFactory::Create(std::move(log_exporter), blp_opts);
  g_logger_provider = logs_sdk::LoggerProviderFactory::Create(std::move(log_processor), res);
  opentelemetry::logs::Provider::SetLoggerProvider(
      std::shared_ptr<opentelemetry::logs::LoggerProvider>(g_logger_provider));

  auto logger = g_logger_provider->GetLogger(kScope, "");
  logger->Info(kStartupMessage);
}

void shutdownOpenTelemetry() noexcept {
  const std::chrono::milliseconds flush_timeout(2000);
  if (g_tracer_provider) {
    g_tracer_provider->ForceFlush(
        std::chrono::duration_cast<std::chrono::microseconds>(flush_timeout));
  }
  if (g_logger_provider) {
    g_logger_provider->ForceFlush(
        std::chrono::duration_cast<std::chrono::microseconds>(flush_timeout));
  }
  g_tracer_provider.reset();
  g_logger_provider.reset();
  trace::Provider::SetTracerProvider(std::shared_ptr<opentelemetry::trace::TracerProvider>());
  opentelemetry::logs::Provider::SetLoggerProvider(
      std::shared_ptr<opentelemetry::logs::LoggerProvider>());
}
#endif  // RGHW_WITH_OPENTELEMETRY

[[maybe_unused]] std::string envEndpoint() {
  const char* env = std::getenv("OTEL_EXPORTER_OTLP_ENDPOINT");
  if (env != nullptr && *env != '\0') {
    return std::string(env);
  }
  return std::string(kDefaultEndpoint);
}

// Strip a leading scheme and trailing '/' so the value can be used as an
// OTLP/gRPC endpoint target (host:port) and as an HTTP URL host:port.
[[maybe_unused]] std::string stripScheme(const std::string& endpoint) {
  std::string s = endpoint;
  if (const auto pos = s.find("://"); pos != std::string::npos) {
    s = s.substr(pos + 3);
  }
  while (!s.empty() && s.back() == '/') {
    s.pop_back();
  }
  return s;
}

[[maybe_unused]] std::string utcTimestamp() {
  const std::time_t now = std::time(nullptr);
  std::tm tm{};
  gmtime_r(&now, &tm);
  char buf[32];
  std::strftime(buf, sizeof(buf), "%Y-%m-%dT%H:%M:%SZ", &tm);
  return std::string(buf);
}

[[maybe_unused]] std::string jsonEscape(const std::string& value) {
  std::string out;
  out.reserve(value.size() + 2);
  for (char c : value) {
    switch (c) {
      case '"':
        out += "\\\"";
        break;
      case '\\':
        out += "\\\\";
        break;
      case '\b':
        out += "\\b";
        break;
      case '\f':
        out += "\\f";
        break;
      case '\n':
        out += "\\n";
        break;
      case '\r':
        out += "\\r";
        break;
      case '\t':
        out += "\\t";
        break;
      default:
        if (static_cast<unsigned char>(c) < 0x20) {
          char buf[8];
          std::snprintf(buf, sizeof(buf), "\\u%04x",
                        static_cast<unsigned int>(static_cast<unsigned char>(c)));
          out += buf;
        } else {
          out += c;
        }
    }
  }
  return out;
}

[[maybe_unused]] std::string otlpLogsJson(const std::string& serviceName) {
  return std::string(
      "{"
      "\"resourceLogs\":[{"
      "\"resource\":{\"attributes\":[{\"key\":\"service.name\","
      "\"value\":{\"stringValue\":\"" +
      jsonEscape(serviceName) +
      "\"}}]},"
      "\"scopeLogs\":[{\"logRecords\":[{\"severityNumber\":" +
      std::to_string(kSeverityInfo) + ",\"severityText\":\"Info\",\"body\":{\"stringValue\":\"" +
      jsonEscape(kStartupMessage) +
      "\"}}]}"
      "}]}");
}

}  // namespace

std::string startupLogLine(const std::string& serviceName) {
  return std::string("{\"level\":\"INFO\",\"service.name\":\"") + jsonEscape(serviceName) +
         "\",\"body\":\"geometry-engine startup\",\"time\":\"" + utcTimestamp() + "\"}";
}

void initialize(const std::string& serviceName, const std::string& otlpEndpoint) noexcept {
  if (g_started) {
    return;
  }
  g_started = true;

  const std::string name = serviceName.empty() ? std::string(kServiceName) : serviceName;
  const std::string endpoint = otlpEndpoint.empty() ? envEndpoint() : otlpEndpoint;

#if defined(RGHW_WITH_OPENTELEMETRY)
  // OTLP/gRPC exporter backed by the OpenTelemetry C++ SDK. Wrap in try/catch
  // so a collector-rejection or SDK failure cannot bring down the service; the
  // catch falls back to the same structured stderr baseline.
  try {
    initOpenTelemetry(name, stripScheme(endpoint));
  } catch (const std::exception& error) {
    std::cerr << "[otel] OpenTelemetry SDK initialization failed: " << error.what() << '\n';
    std::cerr << startupLogLine(name) << '\n';
    std::cerr.flush();
  } catch (...) {
    std::cerr << "[otel] OpenTelemetry SDK initialization failed (unknown error)\n";
    std::cerr << startupLogLine(name) << '\n';
    std::cerr.flush();
  }
#elif defined(RGHW_WITH_CURL_OTLP)
  // Dependency-free fallback: emit the structured startup line to stderr, then
  // best-effort POST an OTLP/JSON log record over HTTP. The HTTP push runs on
  // a detached thread with a short timeout so an unreachable collector can
  // never block startup or shutdown.
  std::cerr << startupLogLine(name) << '\n';
  std::cerr.flush();
  try {
    const std::string target = stripScheme(endpoint);
    std::string host = target;
    if (host.size() >= 5 && host.compare(host.size() - 5, 5, ":4317") == 0) {
      host.replace(host.size() - 5, 5, ":4318");
    }
    const std::string url = "http://" + host + "/v1/logs";
    const std::string body = otlpLogsJson(name);
    std::thread([url, body] {
      try {
        CURL* curl = curl_easy_init();
        if (curl == nullptr) {
          return;
        }
        struct curl_slist* headers = nullptr;
        headers = curl_slist_append(headers, "Content-Type: application/json");
        curl_easy_setopt(curl, CURLOPT_URL, url.c_str());
        curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
        curl_easy_setopt(curl, CURLOPT_POSTFIELDS, body.c_str());
        curl_easy_setopt(curl, CURLOPT_TIMEOUT_MS, 2000L);
        curl_easy_setopt(curl, CURLOPT_CONNECTTIMEOUT_MS, 2000L);
        curl_easy_setopt(curl, CURLOPT_NOSIGNAL, 1L);
        curl_easy_perform(curl);
        curl_slist_free_all(headers);
        curl_easy_cleanup(curl);
      } catch (...) {
        // Best-effort export; never propagate failures from the worker thread.
      }
    }).detach();
  } catch (...) {
    std::cerr << "[otel] failed to schedule OTLP HTTP export; service continues\n";
  }
#else
  // No SDK and no curl available: emit the structured startup line to stderr
  // and leave a single warning. The service runs normally with stderr-based
  // observability.
  std::cerr << startupLogLine(name) << '\n';
  std::cerr.flush();
  std::cerr << "[otel] no OTLP exporter available (OTel SDK disabled and libcurl "
               "not found); structured startup log emitted to stderr, collector "
               "export skipped; endpoint="
            << endpoint << "\n";
#endif
}

void shutdown() noexcept {
  if (!g_started) {
    return;
  }
  g_started = false;
#if defined(RGHW_WITH_OPENTELEMETRY)
  shutdownOpenTelemetry();
#endif
}

}  // namespace telemetry
}  // namespace rghw
