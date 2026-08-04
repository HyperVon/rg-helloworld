#!/usr/bin/env bash
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

REQUIRED_TOOLS=(
  "go:Go toolchain (1.26.5)"
  "java:JDK 21+"
  "javac:JDK 21+"
  "mvn:Apache Maven (3.9.16)"
  "cmake:CMake (4.4.2)"
  "clang-format:clang-format (22.1.8)"
  "python3:Python 3.13+"
  "node:Node.js 24 LTS"
  "npm:npm"
  "ruby:Ruby 3.4+"
  "bundle:Bundler"
  "cargo:Cargo (Rust 1.97.1)"
  "rustc:rustc (Rust 1.97.1)"
  "dotnet:.NET SDK 10.0.302"
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
  for dir in ocr-worker-node event-gateway-node; do
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
  if [ ! -f "$ROOT_DIR/services/adjudicator-ruby/Gemfile.lock" ]; then
    echo ">> bundle install (adjudicator-ruby)"
    (cd "$ROOT_DIR/services/adjudicator-ruby" && bundle install)
  else
    echo ">> bundle dependencies present (adjudicator-ruby)"
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
setup_ruby
setup_gradle_wrapper

echo ""
echo "Summary: $PASS required tools found, $MISSING missing"
if [ "$MISSING" -gt 0 ]; then
  echo "Missing required tools: $MISSING (see [FAIL] rows above)"
  echo "Suggested: brew install <tool>; rustup toolchain install 1.97.1; ~/.dotnet via dotnet-install.sh"
  exit 2
fi
echo "prerequisites: OK"
