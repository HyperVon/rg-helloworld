#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Derive printed toolchain labels from versions.env (single source of truth)
# instead of hardcoding pins that drift from the real versions.
set +e
# shellcheck disable=SC1091
source "$ROOT_DIR/versions.env" 2>/dev/null
set -e

REQUIRED_TOOLS=(
  "go:Go toolchain (${GO_VERSION})"
  "java:JDK ${JAVA_VERSION}+"
  "javac:JDK ${JAVA_VERSION}+"
  "mvn:Apache Maven (${MAVEN_VERSION})"
  "cmake:CMake (${CMAKE_VERSION})"
  "clang-format:clang-format (${CLANG_FORMAT_VERSION})"
  "python3:Python ${PYTHON_VERSION}+"
  "node:Node.js ${NODE_VERSION}"
  "npm:npm"
  "ruby:Ruby ${RUBY_VERSION}+"
  "bundle:Bundler"
  "cargo:Cargo (Rust ${RUST_VERSION})"
  "rustc:rustc (Rust ${RUST_VERSION})"
  "dotnet:.NET SDK ${DOTNET_SDK_VERSION}"
)

OPTIONAL_TOOLS=(
  "docker:Docker (Milestone 2+)"
  "kubectl:kubectl (Milestone 2+)"
  "terraform:Terraform (Milestone 2+)"
  "k3d:k3d (Milestone 2+)"
  "shellcheck:shellcheck (repo lint)"
  "markdownlint-cli2:markdownlint-cli2 (repo lint)"
  "gcovr:gcovr (C++ coverage gate, CI only)"
  "gradle:Gradle (wrapper is used instead; system Gradle optional)"
)

PASS=0
MISSING=0
OPT_MISSING=0

find_tool() {
  local tool="$1"
  if command -v "$tool" >/dev/null 2>&1; then
    command -v "$tool"
    return 0
  fi
  case "$tool" in
    cargo|rustc) [ -x "$HOME/.cargo/bin/$tool" ] && echo "$HOME/.cargo/bin/$tool" && return 0 ;;
    dotnet) [ -x "$HOME/.dotnet/dotnet" ] && echo "$HOME/.dotnet/dotnet" && return 0 ;;
  esac
  return 1
}

check_tool() {
  local tool="$1"
  local label="$2"
  local required="$3"
  if path="$(find_tool "$tool")"; then
    PASS=$((PASS + 1))
    printf "  [ ok ] %-16s %s (%s)\n" "$tool" "$label" "$path"
  else
    if [ "$required" -eq 1 ]; then
      MISSING=$((MISSING + 1))
      printf "  [FAIL] %-16s %s\n" "$tool" "$label"
    else
      OPT_MISSING=$((OPT_MISSING + 1))
      printf "  [skip] %-16s %s\n" "$tool" "$label"
    fi
  fi
}

setup_venv() {
  if [ ! -x "$ROOT_DIR/.venv/bin/ruff" ]; then
    echo ">> creating Python venv and installing pinned dev tools"
    python3 -m venv "$ROOT_DIR/.venv"
    "$ROOT_DIR/.venv/bin/pip" install --quiet -r "$ROOT_DIR/services/image-pipeline-python/requirements-dev.txt"
  else
    echo ">> Python venv already prepared"
  fi
}

setup_node() {
  for dir in ocr-worker-node event-gateway-node telemetry-element; do
    if [ ! -f "$ROOT_DIR/services/$dir/package-lock.json" ]; then
      echo ">> npm install (generates package-lock.json) ($dir)"
      (cd "$ROOT_DIR/services/$dir" && npm install --no-audit --no-fund)
    elif [ ! -d "$ROOT_DIR/services/$dir/node_modules" ]; then
      echo ">> npm ci ($dir)"
      (cd "$ROOT_DIR/services/$dir" && npm ci --no-audit --no-fund)
    else
      echo ">> node_modules present ($dir)"
    fi
  done
}

setup_ruby() {
  local dir="$1"
  if [ ! -f "$ROOT_DIR/services/$dir/Gemfile.lock" ]; then
    echo ">> bundle install ($dir)"
    (cd "$ROOT_DIR/services/$dir" && bundle install)
  else
    echo ">> bundle dependencies present ($dir)"
  fi
}

setup_gradle_wrapper() {
  if [ -x "$ROOT_DIR/services/run-orchestrator-kotlin/gradlew" ]; then
    echo ">> Gradle wrapper present (run-orchestrator-kotlin)"
  else
    echo ">> ERROR: Gradle wrapper missing; run: gradle wrapper --gradle-version 9.6.1"
    exit 2
  fi
}

echo "Rube Goldberg Hello World - prerequisites"
echo ""
echo "Required toolchains:"
for entry in "${REQUIRED_TOOLS[@]}"; do
  check_tool "${entry%%:*}" "${entry#*:}" 1
done

echo ""
echo "Optional tools (needed in later milestones):"
for entry in "${OPTIONAL_TOOLS[@]}"; do
  check_tool "${entry%%:*}" "${entry#*:}" 0
done

echo ""
echo "Preparing language-level dependencies:"
mkdir -p "$ROOT_DIR/.local/diagnostics"
setup_venv
setup_node
for dir in adjudicator-ruby artifact-inspector-ruby; do
  setup_ruby "$dir"
done
setup_gradle_wrapper

echo ""
echo "Summary: $PASS required tools found, $MISSING missing"
if [ "$MISSING" -gt 0 ]; then
  echo "Missing required tools: $MISSING (see [FAIL] rows above)"
  echo "Suggested: brew install <tool>; rustup toolchain install 1.97.1; ~/.dotnet via dotnet-install.sh"
  exit 2
fi
echo "prerequisites: OK"
