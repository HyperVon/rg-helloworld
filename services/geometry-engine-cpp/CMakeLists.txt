cmake_minimum_required(VERSION 3.20)
project(geometry_engine VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

find_package(Threads REQUIRED)
find_path(RDKAFKA_INCLUDE_DIR rdkafka.h HINTS /opt/homebrew/include /usr/local/include /usr/include
          PATH_SUFFIXES librdkafka)
find_library(RDKAFKA_LIBRARY NAMES rdkafka HINTS /opt/homebrew/lib /usr/local/lib /usr/lib)
if(NOT RDKAFKA_INCLUDE_DIR OR NOT RDKAFKA_LIBRARY)
  message(FATAL_ERROR "librdkafka not found (brew install librdkafka / apt install librdkafka-dev)")
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

add_executable(geometry_engine src/main.cpp)
target_link_libraries(geometry_engine PRIVATE geometry_lib)

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

option(ENABLE_COVERAGE "Build with coverage instrumentation" OFF)
if(ENABLE_COVERAGE AND CMAKE_CXX_COMPILER_ID MATCHES "GNU")
  add_compile_options(--coverage -O0)
  add_link_options(--coverage)
endif()
