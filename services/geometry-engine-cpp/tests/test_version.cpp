#include <iostream>
#include <string_view>

#include "geometry_engine/version.hpp"

int main() {
  if (geometry_engine::kVersion.empty()) {
    std::cerr << "version must not be empty\n";
    return 1;
  }
  if (geometry_engine::kVersion != std::string_view{"0.1.0-milestone5"}) {
    std::cerr << "unexpected version: " << geometry_engine::kVersion << '\n';
    return 1;
  }
  if (geometry_engine::kBanner != std::string_view{"geometry-engine 0.1.0-milestone5"}) {
    std::cerr << "unexpected banner: " << geometry_engine::kBanner << '\n';
    return 1;
  }
  return 0;
}
