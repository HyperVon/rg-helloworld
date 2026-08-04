cmake_minimum_required(VERSION 3.20)
project(geometry_engine VERSION 0.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

add_executable(geometry_engine src/main.cpp)
target_include_directories(geometry_engine PRIVATE include)

enable_testing()
add_executable(geometry_engine_version_test tests/test_version.cpp)
target_include_directories(geometry_engine_version_test PRIVATE include)
add_test(NAME version COMMAND geometry_engine_version_test)
add_test(NAME banner COMMAND geometry_engine version)

if(CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
  target_compile_options(geometry_engine PRIVATE -Wall -Wextra -Wpedantic -Werror)
  target_compile_options(geometry_engine_version_test PRIVATE -Wall -Wextra -Wpedantic -Werror)
endif()

option(ENABLE_COVERAGE "Build with coverage instrumentation" OFF)
if(ENABLE_COVERAGE AND CMAKE_CXX_COMPILER_ID MATCHES "GNU")
  target_compile_options(geometry_engine PRIVATE --coverage -O0)
  target_compile_options(geometry_engine_version_test PRIVATE --coverage -O0)
  target_link_options(geometry_engine PRIVATE --coverage)
  target_link_options(geometry_engine_version_test PRIVATE --coverage)
endif()
