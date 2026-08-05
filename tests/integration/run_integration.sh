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
check "glyph-catalog" "glyph-catalog 0.1.0-milestone4" java -jar "$ROOT/services/glyph-catalog-java/target/glyph-catalog-java-0.1.0-milestone4.jar" version
check "run-orchestrator" "run-orchestrator 0.2.0-milestone4" "$ROOT/services/run-orchestrator-kotlin/build/install/run-orchestrator/bin/run-orchestrator" version
check "geometry-engine" "geometry-engine 0.0.0-skeleton (Milestone 0 skeleton)" "$ROOT/.local/build/geometry-engine-cpp/geometry_engine"
check "rasterizer" "rasterizer 0.0.0-skeleton (Milestone 0 skeleton)" "$DOTNET" "$ROOT/services/rasterizer-dotnet/cli/bin/Debug/net10.0/rasterizer.Cli.dll"
check_eval "image-pipeline" "image-pipeline 0.0.0-skeleton (Milestone 0 skeleton)" "PYTHONPATH=$ROOT/services/image-pipeline-python/src python3 -c 'import rg_image_pipeline as m; print(m.banner())'"
check_eval "ocr-worker" "ocr-worker 0.0.0-skeleton (Milestone 0 skeleton)" "node -e \"import('$ROOT/services/ocr-worker-node/out/src/index.js').then(m => console.log(m.banner()))\""
check_eval "event-gateway" "event-gateway 0.0.0-skeleton (Milestone 0 skeleton)" "node -e \"import('$ROOT/services/event-gateway-node/out/src/index.js').then(m => console.log(m.banner()))\""
check_eval "adjudicator" "adjudicator 0.0.0-skeleton (Milestone 0 skeleton)" "cd '$ROOT/services/adjudicator-ruby' && ruby -Ilib -e 'require \"adjudicator\"; puts Adjudicator.banner'"
check "phrase-assembler" "phrase-assembler 0.0.0-skeleton (Milestone 0 skeleton)" "$ROOT/services/phrase-assembler-rust/target/debug/phrase-assembler"

echo ""
echo "Verifying SOAP glyph catalog round trip:"

if command -v java >/dev/null 2>&1 && command -v curl >/dev/null 2>&1; then
  CATALOG_PORT=18083
  GLYPH_CATALOG_PORT=$CATALOG_PORT GLYPH_CATALOG_DB_URL=jdbc:h2:mem:integration \
    java -jar "$ROOT/services/glyph-catalog-java/target/glyph-catalog-java-0.1.0-milestone4.jar" \
    >/tmp/rghello-catalog.log 2>&1 &
  CATALOG_PID=$!
  READY=""
  for _ in $(seq 1 30); do
    if curl -sf "http://127.0.0.1:$CATALOG_PORT/healthz" >/dev/null 2>&1; then
      READY="yes"
      break
    fi
    sleep 1
  done
  if [ -z "$READY" ]; then
    FAILED=$((FAILED + 1))
    say "[FAIL] glyph catalog did not become ready (see /tmp/rghello-catalog.log)"
  else
    SOAP_RESPONSE=$(curl -sf -H "Content-Type: text/xml" \
      -d '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:glyph="urn:rube-goldberg:glyph-catalog:v1"><soapenv:Body><glyph:PlanPhraseRequest><glyph:message>Hello World</glyph:message><glyph:alphabet>RUBE_SIMPLEX_V1</glyph:alphabet><glyph:variant>PRIMARY</glyph:variant></glyph:PlanPhraseRequest></soapenv:Body></soapenv:Envelope>' \
      "http://127.0.0.1:$CATALOG_PORT/ws/glyph-catalog" 2>/dev/null)
    if [ -z "$SOAP_RESPONSE" ]; then
      FAILED=$((FAILED + 1))
      say "[FAIL] SOAP PlanPhrase request returned no response"
    else
      GLYPH_COUNT=$(printf '%s' "$SOAP_RESPONSE" | grep -oE "<[a-zA-Z0-9]+:glyphInstanceId>" | wc -l | tr -d ' ')
      if [ "$GLYPH_COUNT" = "11" ]; then
        say "[ ok ] PlanPhrase returned 11 glyph records"
      else
        FAILED=$((FAILED + 1))
        say "[FAIL] PlanPhrase returned $GLYPH_COUNT glyph records, expected 11"
      fi
      MISSING_POSITION=""
      for i in 0 1 2 3 4 5 6 7 8 9 10; do
        if ! printf '%s' "$SOAP_RESPONSE" | grep -q "position>$i<"; then
          MISSING_POSITION="$MISSING_POSITION $i"
        fi
      done
      if [ -z "$MISSING_POSITION" ]; then
        say "[ ok ] Blueprint positions 0..10 present in order"
      else
        FAILED=$((FAILED + 1))
        say "[FAIL] Missing blueprint positions:$MISSING_POSITION"
      fi
      if printf '%s' "$SOAP_RESPONSE" | grep -q "kind>GAP<"; then
        say "[ ok ] Gap blueprint present"
      else
        FAILED=$((FAILED + 1))
        say "[FAIL] No gap blueprint in PlanPhrase response"
      fi
    fi
  fi
  kill "$CATALOG_PID" 2>/dev/null || true
  wait "$CATALOG_PID" 2>/dev/null || true
else
  skip "Java or curl for SOAP round trip"
fi

echo ""
echo "Integration results: failures=$FAILED skipped=$SKIPPED"
if [ "$FAILED" -gt 0 ]; then
  echo "integration: FAIL"
  exit 1
fi
echo "integration: OK"
