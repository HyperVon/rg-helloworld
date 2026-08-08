cmake_minimum_required(VERSION 3.20)
project(geometry_engine VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

find_package(Threads REQUIRED)
find_path(RDKAFKA_INCLUDE_DIR rdkafka.h HINTS /opt/homebrew/include /usr/local/include /usr/include
        PATH_SUFFIXES librdkafka)
find_library(RDKAFKA_LIBRARY NAMES rdkafka HINTES /opt/homebrew/lib /usr/local/lib /usr/lib)
if(NOT RDKAFKA_INCLUDE_DIR OR NOT RDKAFKA_LIBRARY)
  message(FATAL_ERROR "librdkafka not found (brew install librdkafka / apt install librdkafka-dev)")
endif()

# OpenTelemetry is opt-in and off by default so the service builds and runs
# fully offline. When enabled, the C++ SDK (pinned to v1.16.0) is fetched from
# GitHub via FetchContent; if that fetch is unavailable, leave the option off
# and the service ships the dependency-free fallback telemetry instead.
option(GEOMETRY_ENGINE_TELEMETRY_OTEL "Fetch + link the OpenTelemetry C++ SDK (v1.16.0) for OTLP/gRPC export" OFF)
if(GEOMETRY_ENGINE_TELEMETRY_OTEL)
  include(FetchContent)
  FetchContent_Declare(opentelemetry-cpp
    GIT_REPOSITORY https://github.com/open-telemetry/opentelemetry-cpp.git
    GIT_TAG v1.16.0)
  set(BUILD_TESTING OFF CACHE BOOL "" FORCE)
  set(OPENTELEMETRY_BUILD_TESTS OFF CACHE BOOL "" FORCE)
  set(OPENTELEMETRY_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
  set(OPENTELEMETRY_BUILD_BENCHMARKS OFF CACHE BOOL "" FORCE)
  set(OPENTELEMETRY_CPP_BUILD_API ON CACHE BOOL "" FORCE)
  set(WITH_OTLP ON CACHE BOOL "" FORCE)
  set(WITH_OTLP_HTTP OFF CACHE BOOL "" FORCE)
  set(WITH_ZPAGE OFF CACHE BOOL "" FORCE)
  set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
  FetchContent_MakeAvailable(opentelemetry-cpp)
  set(RGHW_TELEMETRY_FEATURE_OTEL TRUE)
endif()

# libcurl is optional: when present (and OTel is disabled) the fallback
# telemetry posts OTLP/JSON log records over HTTP to the collector.
find_package(CURL QUIET)
if(CURL_FOUND AND NOT RGHW_TELEMETRY_FEATURE_OTEL)
  set(RGHW_TELEMETRY_FEATURE_CURL TRUE)
endif()

option(ENABLE_COVERAGE "Build with coverage instrumentation" OFF)
if(ENABLE_COVERAGE AND CMAKE_CXX_COMPILER_ID MATCHES "GNU")
  add_compile_options(--coverage -O0)
  add_link_options(--coverage)
endif()

add_library(geometry_lib STATIC
  src/json.cpp
  src/sha256.cpp
  src/geometry.cpp
  src/s3.cpp
  src/kafka.cpp
  src/service.cpp)
target_include_directories(geometry_lib PUBLIC include ${RDKAFKA_INCLUDE_DIR})
target_link_libraries(geometry_lib PUBLIC Threads::Threads ${RDKAFKA_LIBRARY})

# Lightweight telemetry: OTLP/gRPC (OTel SDK) when enabled, otherwise a
# dependency-free fallback that emits a structured startup log line and, if
# libcurl is available, best-effort POSTs OTLP/JSON logs over HTTP. The service
# builds and runs offline regardless of collector reachability.
add_library(geometry_engine_telemetry STATIC src/telemetry.cpp)
target_include_directories(geometry_engine_telemetry PUBLIC include src)
target_link_libraries(geometry_engine_telemetry PUBLIC Threads::Threads)
if(RGHW_TELEMETRY_FEATURE_OTEL)
  target_compile_definitions(geometry_engine_telemetry PUBLIC RGHW_WITH_OPENTELEMETRY)
  target_link_libraries(geometry_engine_telemetry PRIVATE
    opentelemetry::otlp_grpc_exporter
    opentelemetry::otlp_grpc_log_record_exporter
    opentelemetry::trace_sdk
    opentelemetry::trace
    opentelemetry::logs_sdk
    opentelemetry::logs
    opentelemetry::resource
  )
endif()
if(RGHW_TELEMETRY_FEATURE_CURL)
  target_compile_definitions(geometry_engine_telemetry PUBLIC RGHW_WITH_CURL_OTLP)
  target_link_libraries(geometry_engine_telemetry PRIVATE CURL::libcurl)
endif()

add_executable(geometry_engine src/main.cpp)
target_link_libraries(geometry_engine PRIVATE geometry_lib geometry_engine_telemetry)

enable_testing()
foreach(test_name json sha256 geometry s3 service version)
  add_executable(geometry_engine_${test_name}_test tests/test_${test_name}.cpp)
  target_link_libraries(geometry_engine_${test_name}_test PRIVATE geometry_lib)
  add_test(NAME ${test_name} COMMAND geometry_engine_${test_name}_test)
endforeach()
add_test(NAME banner COMMAND geometry_engine version)

if(CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
  target_compile_options(geometry_lib PRIVATE -Wall -Wextra -Wpedantic -Werror)
  target_compile_options(geometry_engine PRIVATE -Wall -Wextra -Wpedantic -Werror)
  target_compile_options(geometry_engine_telemetry PRIVATE -Wall -Wextra -Wpedantic -Werror)
  # librdkafka's own headers trip ignored-qualifiers and GNU statement
  # expression warnings; they are external, so downgrade them for this TU.
  if(CMAKE_CXX_COMPILER_ID MATCHES "Clang")
    set_source_files_properties(src/kafka.cpp PROPERTIES
      COMPILE_OPTIONS "-Wno-error=ignored-qualifiers;-Wno-error=gnu-statement-expression-from-macro-expansion")
  else()
    set_source_files_properties(src/kafka.cpp PROPERTIES
      COMPILE_OPTIONS "-Wno-error=ignored-qualifiers;-Wno-error=pedantic")
  endif()
endif()
