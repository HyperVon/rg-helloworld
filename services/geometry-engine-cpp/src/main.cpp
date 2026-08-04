#include <iostream>
#include <string>

#include "geometry_engine/version.hpp"

namespace {

std::string banner() {
  return std::string{"geometry-engine "} + std::string{geometry_engine::kVersion} +
         " (Milestone 0 skeleton)";
}

}  // namespace

int main() {
  std::cout << banner() << '\n';
  return 0;
}
