#pragma once

#include <string_view>

namespace geometry_engine {

// Not constexpr: libc++ (macOS SDK) lacks a constexpr string_view literal
// constructor with checked traits. Namespace-scope const is initialized once
// and is fine for banner/version output.
inline const std::string_view kVersion = "0.1.0-milestone5";
inline const std::string_view kBanner = "geometry-engine 0.1.0-milestone5";

}  // namespace geometry_engine
