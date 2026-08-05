#!/usr/bin/env bash
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BIN="$ROOT/.local/bin"
SKIPPED=0
FAILED=0

say() { printf "  %s\n" "$1"; }

skip() {
  SKIPPED=$((SKIPPED + 1))
  say "[skip] $1"
}

check() {
  local name="$1"
  local expected="$2"
  shift 2
  local actual
  actual="$("$@" 2>/dev/null)"
  if [ "$actual" = "$expected" ]; then
    say "[ ok ] $name"
  else
    FAILED=$((FAILED + 1))
    say "[FAIL] $name: expected '$expected', got '$actual'"
  fi
}

check_eval() {
  local name="$1"
  local expected="$2"
  local actual
  actual="$(eval "$3" 2>/dev/null)"
  if [ "$actual" = "$expected" ]; then
    say "[ ok ] $name"
  else
    FAILED=$((FAILED + 1))
    say "[FAIL] $name: expected '$expected', got '$actual'"
  fi
}

mkdir -p "$BIN"

echo "Rube Goldberg Hello World - integration tests"
echo "Building service artifacts:"

if command -v go >/dev/null 2>&1; then
  (cd "$ROOT/cmd/rghello" && go build -o "$BIN/rghello" .) || exit 1
  (cd "$ROOT/services/vector-normalizer-go" && go build -o "$BIN/vector-normalizer" .) || exit 1
  say "[ ok ] Go binaries"
else
  skip "Go toolchain"
fi

if command -v mvn >/dev/null 2>&1; then
  (cd "$ROOT/services/glyph-catalog-java" && mvn -q -B -DskipTests package) || exit 1
  say "[ ok ] Java jar"
else
  skip "Maven"
fi

if [ -x "$ROOT/services/run-orchestrator-kotlin/gradlew" ]; then
  (cd "$ROOT/services/run-orchestrator-kotlin" && ./gradlew --console=plain -q installDist) || exit 1
  say "[ ok ] Kotlin distribution"
else
  skip "Gradle wrapper"
fi

if command -v cmake >/dev/null 2>&1; then
  cmake -S "$ROOT/services/geometry-engine-cpp" -B "$ROOT/.local/build/geometry-engine-cpp" -DCMAKE_BUILD_TYPE=Release >/dev/null || exit 1
  cmake --build "$ROOT/.local/build/geometry-engine-cpp" >/dev/null || exit 1
  say "[ ok ] C++ binary"
else
  skip "CMake"
fi

DOTNET="$(command -v dotnet 2>/dev/null || echo "$HOME/.dotnet/dotnet")"

if [ -x "$DOTNET" ]; then
  "$DOTNET" build --nologo --verbosity quiet "$ROOT/services/rasterizer-dotnet/cli/rasterizer.Cli.csproj" || exit 1
  say "[ ok ] .NET binary"
else
  skip ".NET SDK"
fi

if command -v python3 >/dev/null 2>&1; then
  say "[ ok ] Python package (no build step)"
else
  skip "Python"
fi

if command -v node >/dev/null 2>&1; then
  for d in ocr-worker-node event-gateway-node; do
    if [ ! -d "$ROOT/services/$d/node_modules" ]; then
      (cd "$ROOT/services/$d" && npm ci --no-audit --no-fund) || exit 1
    fi
    (cd "$ROOT/services/$d" && npm run build --silent) || exit 1
  done
  say "[ ok ] TypeScript builds"
else
  skip "Node.js"
fi

if command -v ruby >/dev/null 2>&1; then
  say "[ ok ] Ruby package (no build step)"
else
  skip "Ruby"
fi

CARGO="${CARGO:-}"
if command -v cargo >/dev/null 2>&1; then
  CARGO="cargo"
elif [ -x "$HOME/.cargo/bin/cargo" ]; then
  CARGO="$HOME/.cargo/bin/cargo"
fi
if [ -n "$CARGO" ]; then
  (cd "$ROOT/services/phrase-assembler-rust" && "$CARGO" build --quiet) || exit 1
  say "[ ok ] Rust binary"
else
  skip "Cargo"
fi

echo "Verifying service banners:"

check "rghello" "rghello 0.0.0-skeleton" "$BIN/rghello" version
check "vector-normalizer" "vector-normalizer 0.0.0-skeleton" "$BIN/vector-normalizer" version
check "glyph-catalog" "glyph-catalog 0.0.0-skeleton" java -jar "$ROOT/services/glyph-catalog-java/target/glyph-catalog-java-0.0.0-skeleton.jar" version
check "run-orchestrator" "run-orchestrator 0.1.0-milestone3" "$ROOT/services/run-orchestrator-kotlin/build/install/run-orchestrator/bin/run-orchestrator" version
check "geometry-engine" "geometry-engine 0.0.0-skeleton (Milestone 0 skeleton)" "$ROOT/.local/build/geometry-engine-cpp/geometry_engine"
check "rasterizer" "rasterizer 0.0.0-skeleton (Milestone 0 skeleton)" "$DOTNET" "$ROOT/services/rasterizer-dotnet/cli/bin/Debug/net10.0/rasterizer.Cli.dll"
check_eval "image-pipeline" "image-pipeline 0.0.0-skeleton (Milestone 0 skeleton)" "PYTHONPATH=$ROOT/services/image-pipeline-python/src python3 -c 'import rg_image_pipeline as m; print(m.banner())'"
check_eval "ocr-worker" "ocr-worker 0.0.0-skeleton (Milestone 0 skeleton)" "node -e \"import('$ROOT/services/ocr-worker-node/out/src/index.js').then(m => console.log(m.banner()))\""
check_eval "event-gateway" "event-gateway 0.0.0-skeleton (Milestone 0 skeleton)" "node -e \"import('$ROOT/services/event-gateway-node/out/src/index.js').then(m => console.log(m.banner()))\""
check_eval "adjudicator" "adjudicator 0.0.0-skeleton (Milestone 0 skeleton)" "cd '$ROOT/services/adjudicator-ruby' && ruby -Ilib -e 'require \"adjudicator\"; puts Adjudicator.banner'"
check "phrase-assembler" "phrase-assembler 0.0.0-skeleton (Milestone 0 skeleton)" "$ROOT/services/phrase-assembler-rust/target/debug/phrase-assembler"

echo ""
echo "Integration results: failures=$FAILED skipped=$SKIPPED"
if [ "$FAILED" -gt 0 ]; then
  echo "integration: FAIL"
  exit 1
fi
echo "integration: OK"
