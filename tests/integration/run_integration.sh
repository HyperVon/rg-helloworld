#!/usr/bin/env bash
# Deliberately no `-e`: this script counts failures via check()/check_eval()
# and continues, so a failing verification must not abort the run. Every
# command whose result feeds a later assertion is explicitly guarded instead.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BIN="$ROOT/.local/bin"
SKIPPED=0
FAILED=0

say() { printf "  %s\n" "$1"; }

pick_free_port() {
  local port
  while :; do
    port=$(( (RANDOM % 10000) + 20000 ))
    if ! (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null; then
      printf '%s\n' "$port"
      return 0
    fi
  done
}

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
  (cd "$ROOT/cmd/rghw" && go build -o "$BIN/rghw" .) || exit 1
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
  for d in ocr-worker-node event-gateway-node telemetry-element; do
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

check "rghw" "rghw 0.0.0-skeleton" "$BIN/rghw" version
check "vector-normalizer" "vector-normalizer 0.2.0-milestone6" "$BIN/vector-normalizer" version
check "glyph-catalog" "glyph-catalog 0.1.0-milestone4" java -jar "$ROOT/services/glyph-catalog-java/target/glyph-catalog-java-0.1.0-milestone4.jar" version
check "run-orchestrator" "run-orchestrator 0.5.0-milestone7" "$ROOT/services/run-orchestrator-kotlin/build/install/run-orchestrator/bin/run-orchestrator" version
check "geometry-engine" "geometry-engine 0.1.0-milestone5" "$ROOT/.local/build/geometry-engine-cpp/geometry_engine" version
check "rasterizer" "rasterizer 0.1.0-milestone11" "$DOTNET" "$ROOT/services/rasterizer-dotnet/cli/bin/Debug/net10.0/rasterizer.Cli.dll" version
check_eval "image-pipeline" "image-pipeline 0.1.0-milestone11" "PYTHONPATH=$ROOT/services/image-pipeline-python/src python3 -c 'import rg_image_pipeline as m; print(m.banner())'"
check_eval "ocr-worker" "ocr-worker 0.5.0-milestone8" "node -e \"import('$ROOT/services/ocr-worker-node/out/index.js').then(m => console.log(m.banner()))\""
check_eval "event-gateway" "event-gateway 0.5.0-milestone11 (Milestone 11)" "node -e \"import('$ROOT/services/event-gateway-node/out/index.js').then(m => console.log(m.banner()))\""
check_eval "adjudicator" "adjudicator 0.5.0-milestone8 (Milestone 8)" "cd '$ROOT/services/adjudicator-ruby' && ruby -Ilib -e 'require \"adjudicator\"; puts Adjudicator.banner'"
check "phrase-assembler" "phrase-assembler 0.5.0-milestone11 (Milestone 11)" "$ROOT/services/phrase-assembler-rust/target/debug/phrase-assembler"
check_eval "telemetry-element" "telemetry-element 0.5.0-milestone11 (Milestone 11)" "cd '$ROOT/services/telemetry-element' && node -e \"const m = require('./out/index.js'); console.log(m.banner())\""
check_eval "artifact-inspector" "artifact-inspector 0.5.0-milestone11 (Milestone 11)" "cd '$ROOT/services/artifact-inspector-ruby' && ruby -Ilib -e 'require \"artifact_inspector\"; puts ArtifactInspector.banner'"

echo ""
echo "Verifying SOAP glyph catalog round trip:"

if command -v java >/dev/null 2>&1 && command -v curl >/dev/null 2>&1; then
  CATALOG_PORT=$(pick_free_port)
  GLYPH_CATALOG_PORT=$CATALOG_PORT GLYPH_CATALOG_DB_URL=jdbc:h2:mem:integration \
    java -jar "$ROOT/services/glyph-catalog-java/target/glyph-catalog-java-0.1.0-milestone4.jar" \
    >/tmp/rghw-catalog.log 2>&1 &
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
    say "[FAIL] glyph catalog did not become ready (see /tmp/rghw-catalog.log)"
  else
    SOAP_RESPONSE=$(curl -sf -H "Content-Type: text/xml" \
      -d '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:glyph="urn:rube-goldberg:glyph-catalog:v1"><soapenv:Body><glyph:PlanPhraseRequest><glyph:message>HELLO WORLD</glyph:message><glyph:alphabet>RUBE_SIMPLEX_V1</glyph:alphabet><glyph:variant>PRIMARY</glyph:variant></glyph:PlanPhraseRequest></soapenv:Body></soapenv:Envelope>' \
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
echo "Verifying Milestone 5 artifact pipeline (--once):"

if [ -x "$ROOT/.local/build/geometry-engine-cpp/geometry_engine" ] && [ -x "$BIN/vector-normalizer" ]; then
  FIXTURE="$ROOT/tests/integration/fixtures/blueprint-event.json"
  GEOMETRY_ONCE="$ROOT/.local/build/geometry-engine-cpp/geometry_engine"
  VENV_PY="$ROOT/.venv/bin/python"

  # Geometry expansion is deterministic: two runs produce identical events.
  GEOM1_OK=0
  GEOM2_OK=0
  "$GEOMETRY_ONCE" --once < "$FIXTURE" > /tmp/rghw-geometry-1.json && GEOM1_OK=1
  "$GEOMETRY_ONCE" --once < "$FIXTURE" > /tmp/rghw-geometry-2.json && GEOM2_OK=1
  if [ "$GEOM1_OK" = 1 ] && [ "$GEOM2_OK" = 1 ] && cmp -s /tmp/rghw-geometry-1.json /tmp/rghw-geometry-2.json; then
    say "[ ok ] geometry-engine --once is deterministic"
  else
    FAILED=$((FAILED + 1))
    say "[FAIL] geometry-engine --once is nondeterministic or failed (run1=$GEOM1_OK run2=$GEOM2_OK)"
  fi

  # The event type and maturity ranks are correct (10 -> 20).
  if grep -q '"type":"rg.geometry-expanded.v1"' /tmp/rghw-geometry-1.json &&
    grep -q '"inputMaturity":10' /tmp/rghw-geometry-1.json &&
    grep -q '"outputMaturity":20' /tmp/rghw-geometry-1.json; then
    say "[ ok ] geometry event type + maturity 10 -> 20"
  else
    FAILED=$((FAILED + 1))
    say "[FAIL] geometry event shape wrong"
  fi

  # Normalization consumes the geometry event and emits the normalized
  # event plus SVG artifacts; deterministic and mature 20 -> 30.
  rm -rf /tmp/rghw-normalized-out
  RUN1_OK=0
  RUN2_OK=0
  "$BIN/vector-normalizer" --once --emit-artifacts-to /tmp/rghw-normalized-out \
    < /tmp/rghw-geometry-1.json > /tmp/rghw-normalized-1.json && RUN1_OK=1
  "$BIN/vector-normalizer" --once --emit-artifacts-to /tmp/rghw-normalized-out-2 \
    < /tmp/rghw-geometry-1.json > /tmp/rghw-normalized-2.json && RUN2_OK=1
  if [ "$RUN1_OK" = 1 ] && [ "$RUN2_OK" = 1 ] && cmp -s /tmp/rghw-normalized-1.json /tmp/rghw-normalized-2.json; then
    say "[ ok ] vector-normalizer --once is deterministic"
  else
    FAILED=$((FAILED + 1))
    say "[FAIL] vector-normalizer --once is nondeterministic or failed (run1=$RUN1_OK run2=$RUN2_OK)"
  fi

  if grep -q '"type":"rg.glyph-normalized.v1"' /tmp/rghw-normalized-1.json &&
    grep -q '"inputMaturity":20' /tmp/rghw-normalized-1.json &&
    grep -q '"outputMaturity":30' /tmp/rghw-normalized-1.json; then
    say "[ ok ] normalized event type + maturity 20 -> 30"
  else
    FAILED=$((FAILED + 1))
    say "[FAIL] normalized event shape wrong"
  fi

  for field in message targetText expectedCharacter unicodeCodePoint characterName glyphLabel; do
    if grep -q "\"$field\"" /tmp/rghw-geometry-1.json /tmp/rghw-normalized-1.json; then
      FAILED=$((FAILED + 1))
      say "[FAIL] prohibited field '$field' present in a downstream event"
    fi
  done
  say "[ ok ] no prohibited fields in geometry or normalized events"

  # Schema validation of the event data payloads.
  if [ -x "$VENV_PY" ] && "$VENV_PY" -c "import jsonschema" >/dev/null 2>&1; then
    if "$VENV_PY" - "$ROOT/contracts/events/geometry-expanded.v1.schema.json" /tmp/rghw-geometry-1.json <<'PYEOF'
import json
import sys
from jsonschema import validate

schema = json.load(open(sys.argv[1]))
event = json.load(open(sys.argv[2]))
validate(instance=event["data"], schema=schema)
PYEOF
    then
      say "[ ok ] geometry event validates against its schema"
    else
      FAILED=$((FAILED + 1))
      say "[FAIL] geometry event failed schema validation"
    fi
    if "$VENV_PY" - "$ROOT/contracts/events/vector-normalized.v1.schema.json" /tmp/rghw-normalized-1.json <<'PYEOF'
import json
import sys
from jsonschema import validate

schema = json.load(open(sys.argv[1]))
event = json.load(open(sys.argv[2]))
validate(instance=event["data"], schema=schema)
PYEOF
    then
      say "[ ok ] normalized event validates against its schema"
    else
      FAILED=$((FAILED + 1))
      say "[FAIL] normalized event failed schema validation"
    fi
  else
    skip "venv jsonschema for event schema validation"
  fi

  # SVG artifacts: no text elements, and sha256 matches the event field.
  SVG_FILE=$(find /tmp/rghw-normalized-out -maxdepth 1 -type f -name '*.svg' -print -quit)
  if [ -n "$SVG_FILE" ]; then
    if grep -q "<text\|<font" "$SVG_FILE"; then
      FAILED=$((FAILED + 1))
      say "[FAIL] SVG artifact contains text elements"
    else
      say "[ ok ] SVG artifact contains no text elements"
    fi
    ACTUAL_SHA=$(shasum -a 256 "$SVG_FILE" | awk '{print $1}')
    EVENT_SHA=$(grep -o '"svgSha256":"[0-9a-f]*"' /tmp/rghw-normalized-1.json | head -1 | sed 's/.*:"//; s/"//')
    if [ "$ACTUAL_SHA" = "$EVENT_SHA" ]; then
      say "[ ok ] SVG artifact sha256 matches the event svgSha256"
    else
      FAILED=$((FAILED + 1))
      say "[FAIL] SVG sha256 $ACTUAL_SHA != event $EVENT_SHA"
    fi
  else
    FAILED=$((FAILED + 1))
    say "[FAIL] no SVG artifact emitted by --emit-artifacts-to"
  fi

  rm -rf /tmp/rghw-normalized-out /tmp/rghw-normalized-out-2
  rm -f /tmp/rghw-geometry-1.json /tmp/rghw-geometry-2.json \
    /tmp/rghw-normalized-1.json /tmp/rghw-normalized-2.json
else
  skip "geometry-engine or vector-normalizer binary (--once pipeline)"
fi

echo ""
echo "Verifying Milestone 6 gRPC rasterization (local rasterizer):"

if [ -x "$BIN/vector-normalizer" ] && [ -x "$DOTNET" ]; then
  RASTERIZER_STORE_DIR=$(mktemp -d /tmp/rghw-raster-store.XXXXXX)
  RASTERIZER_PORT=$(pick_free_port)
  RASTERIZER_STORE=local RASTERIZER_LOCAL_DIR="$RASTERIZER_STORE_DIR" RASTERIZER_PORT=$RASTERIZER_PORT \
    "$DOTNET" "$ROOT/services/rasterizer-dotnet/cli/bin/Debug/net10.0/rasterizer.Cli.dll" serve \
    >/tmp/rghw-rasterizer.log 2>&1 &
  RASTERIZER_PID=$!
  READY=""
  for _ in $(seq 1 30); do
    # bash built-in TCP probe; nc is not installed everywhere (e.g. Arch)
    if (exec 3<>"/dev/tcp/127.0.0.1/$RASTERIZER_PORT") 2>/dev/null; then
      READY="yes"
      break
    fi
    sleep 1
  done
  if [ -z "$READY" ]; then
    FAILED=$((FAILED + 1))
    say "[FAIL] rasterizer did not become ready (see /tmp/rghw-rasterizer.log)"
    kill "$RASTERIZER_PID" 2>/dev/null || true
  else
    say "[ ok ] rasterizer gRPC server ready on :$RASTERIZER_PORT"

    # Re-run geometry expansion so the normalized pipeline gets a fresh
    # drawable geometry event, then rasterize it over the real gRPC contract.
    FIXTURE="$ROOT/tests/integration/fixtures/blueprint-event.json"
    GEOMETRY_ONCE="$ROOT/.local/build/geometry-engine-cpp/geometry_engine"
    if [ -x "$GEOMETRY_ONCE" ]; then
      "$GEOMETRY_ONCE" --once < "$FIXTURE" > /tmp/rghw-m6-geometry.json
    else
      say "[skip] geometry-engine binary missing for M6 geometry input"
      cp /dev/null /tmp/rghw-m6-geometry.json
    fi
    if [ -s /tmp/rghw-m6-geometry.json ]; then
      RASTER1_OK=0
      RASTER2_OK=0
      "$BIN/vector-normalizer" --once --rasterizer-url "127.0.0.1:$RASTERIZER_PORT" \
        < /tmp/rghw-m6-geometry.json > /tmp/rghw-raster-1.json && RASTER1_OK=1
      "$BIN/vector-normalizer" --once --rasterizer-url "127.0.0.1:$RASTERIZER_PORT" \
        < /tmp/rghw-m6-geometry.json > /tmp/rghw-raster-2.json && RASTER2_OK=1

      RASTER_LINES=$(wc -l < /tmp/rghw-raster-1.json | tr -d ' ')
      if [ "$RASTER_LINES" = "2" ]; then
        say "[ ok ] --once --rasterizer-url emitted normalized + rasterized events"
      else
        FAILED=$((FAILED + 1))
        say "[FAIL] expected 2 output lines, got $RASTER_LINES"
      fi

      # The second line is the rasterized event.
      RASTER_EVENT=$(sed -n 2p /tmp/rghw-raster-1.json)
      if [ -n "$RASTER_EVENT" ] &&
        printf '%s' "$RASTER_EVENT" | grep -q '"type":"rg.glyph-rasterized.v1"' &&
        printf '%s' "$RASTER_EVENT" | grep -q '"inputMaturity":30' &&
        printf '%s' "$RASTER_EVENT" | grep -q '"outputMaturity":40'; then
        say "[ ok ] rasterized event type + maturity 30 -> 40"
      else
        FAILED=$((FAILED + 1))
        say "[FAIL] rasterized event shape wrong"
      fi

      # Idempotency: the same request produces the identical event.
      if [ "$RASTER1_OK" = 1 ] && [ "$RASTER2_OK" = 1 ] && cmp -s /tmp/rghw-raster-1.json /tmp/rghw-raster-2.json; then
        say "[ ok ] --once --rasterizer-url is deterministic"
      else
        FAILED=$((FAILED + 1))
        say "[FAIL] duplicate rasterization is nondeterministic or failed (run1=$RASTER1_OK run2=$RASTER2_OK)"
      fi

      # The PNG artifact exists in the local store under the event key and
      # matches the reported sha256 (byte-identical duplicates too).
      OBJECT_KEY=$(printf '%s' "$RASTER_EVENT" | grep -o '"objectKey":"[^"]*"' | head -1 | sed 's/.*:"//; s/"//')
      RASTER_SHA=$(printf '%s' "$RASTER_EVENT" | grep -o '"sha256":"[0-9a-f]*"' | head -1 | sed 's/.*:"//; s/"//')
      PNG_FILE="$RASTERIZER_STORE_DIR/$OBJECT_KEY"
      if [ -f "$PNG_FILE" ]; then
        MAGIC=$(head -c 8 "$PNG_FILE" | xxd -p | tr -d '\n')
        if [ "$MAGIC" = "89504e470d0a1a0a" ]; then
          say "[ ok ] rasterized PNG artifact present with PNG magic bytes"
        else
          FAILED=$((FAILED + 1))
          say "[FAIL] PNG magic bytes wrong: $MAGIC"
        fi
        ACTUAL_SHA=$(shasum -a 256 "$PNG_FILE" | awk '{print $1}')
        if [ "$ACTUAL_SHA" = "$RASTER_SHA" ]; then
          say "[ ok ] PNG sha256 matches the event raster.sha256"
        else
          FAILED=$((FAILED + 1))
          say "[FAIL] PNG sha256 $ACTUAL_SHA != event $RASTER_SHA"
        fi
      else
        FAILED=$((FAILED + 1))
        say "[FAIL] PNG artifact missing at $OBJECT_KEY"
      fi

      for field in message targetText expectedCharacter unicodeCodePoint characterName glyphLabel; do
        if printf '%s' "$RASTER_EVENT" | grep -q "\"$field\""; then
          FAILED=$((FAILED + 1))
          say "[FAIL] prohibited field '$field' present in the rasterized event"
        fi
      done
      say "[ ok ] no prohibited fields in the rasterized event"

      # Schema validation of the rasterized event data payload.
      if [ -x "$VENV_PY" ] && "$VENV_PY" -c "import jsonschema" >/dev/null 2>&1; then
        printf '%s\n' "$RASTER_EVENT" > /tmp/rghw-raster-event.json
        if "$VENV_PY" - "$ROOT/contracts/events/glyph-rasterized.v1.schema.json" /tmp/rghw-raster-event.json <<'PYEOF'
import json
import sys
from jsonschema import validate

schema = json.load(open(sys.argv[1]))
event = json.load(open(sys.argv[2]))
validate(instance=event["data"], schema=schema)
PYEOF
        then
          say "[ ok ] rasterized event validates against its schema"
        else
          FAILED=$((FAILED + 1))
          say "[FAIL] rasterized event failed schema validation"
        fi
        rm -f /tmp/rghw-raster-event.json
      else
        skip "venv jsonschema for rasterized event schema validation"
      fi

      # Gap geometry is normalized but never rasterized.
      sed 's/"kind"[[:space:]]*:[[:space:]]*"DRAWABLE_GEOMETRY"/"kind": "GAP_GEOMETRY"/' /tmp/rghw-m6-geometry.json \
        > /tmp/rghw-m6-gap.json
      "$BIN/vector-normalizer" --once --rasterizer-url "127.0.0.1:$RASTERIZER_PORT" \
        < /tmp/rghw-m6-gap.json > /tmp/rghw-raster-gap.json
      GAP_LINES=$(wc -l < /tmp/rghw-raster-gap.json | tr -d ' ')
      if [ "$GAP_LINES" = "1" ]; then
        say "[ ok ] gap geometry skips rasterization"
      else
        FAILED=$((FAILED + 1))
        say "[FAIL] gap geometry produced $GAP_LINES output lines, want 1"
      fi

      rm -f /tmp/rghw-m6-geometry.json /tmp/rghw-m6-gap.json \
        /tmp/rghw-raster-1.json /tmp/rghw-raster-2.json /tmp/rghw-raster-gap.json
    else
      FAILED=$((FAILED + 1))
      say "[FAIL] geometry-engine --once produced no geometry input"
    fi
  fi
  kill "$RASTERIZER_PID" 2>/dev/null || true
  wait "$RASTERIZER_PID" 2>/dev/null || true
  rm -rf "$RASTERIZER_STORE_DIR"
else
  skip "vector-normalizer or dotnet for M6 gRPC pipeline"
fi

echo ""
echo "Verifying Milestone 7 composition and preprocessing (--once):"

if command -v python3 >/dev/null 2>&1 && [ -f "$ROOT/services/image-pipeline-python/src/rg_image_pipeline/__init__.py" ]; then
  # Create fixture glyph inputs (simulating rasterized glyph outputs)
  # We create 11 JSON fixtures: 10 drawables + 1 gap, matching "HELLO WORLD"
  M7_FIXTURES="/tmp/rghw-m7-glyphs"
  mkdir -p "$M7_FIXTURES"

  # Generate fixtures using a helper Python script
  python3 -c "
import sys, json, struct, zlib, os

out_dir = '$M7_FIXTURES'

def make_png(width, height, fill=(128, 128, 128, 255)):
    raw = b''
    for _ in range(height):
        raw += b'\x00'
        for _ in range(width):
            raw += bytes(fill)
    def chunk(ctype, data):
        c = ctype + data
        return struct.pack('>I', len(data)) + c + struct.pack('>I', zlib.crc32(c) & 0xffffffff)
    sig = b'\x89PNG\r\n\x1a\n'
    ihdr = struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0)
    idat = zlib.compress(raw)
    return (sig + chunk(b'IHDR', ihdr) + chunk(b'IDAT', idat) + chunk(b'IEND', b'')).hex()

png_hex = make_png(100, 100)
for pos in range(11):
    if pos == 5:
        fixture = {
            'position': 5,
            'glyphInstanceId': 'gap-5',
            'object_key': '',
            'sha256': '',
            'width': 0,
            'height': 0,
            'advance_width': 0.6,
            'baseline': 0.0,
            'kind': 'GAP',
            'image_bytes': None,
        }
    else:
        fixture = {
            'position': pos,
            'glyphInstanceId': f'glyph-{pos}',
            'object_key': f'artifacts/glyph-{pos}.png',
            'sha256': '',
            'width': 100,
            'height': 100,
            'advance_width': 1.0,
            'baseline': 80.0,
            'kind': 'DRAWABLE',
            'image_bytes': png_hex,
        }
    with open(os.path.join(out_dir, f'glyph-{pos}.json'), 'w') as f:
        json.dump(fixture, f, indent=2, sort_keys=True)
print('fixtures created')
"

  if [ -x "$BIN/image-pipeline" ]; then
    IMAGE_PIPELINE="$BIN/image-pipeline"
  elif [ -x "$ROOT/.venv/bin/python" ]; then
    IMAGE_PIPELINE="PYTHONPATH=$ROOT/services/image-pipeline-python/src $ROOT/.venv/bin/python -m rg_image_pipeline.cli"
  else
    IMAGE_PIPELINE="PYTHONPATH=$ROOT/services/image-pipeline-python/src python3 -m rg_image_pipeline.cli"
  fi

  # shellcheck disable=SC2012 # find loses sort order for glyph fixtures, ls is safe for alphanumeric names
  GLYPH_LIST=$(ls "$M7_FIXTURES"/glyph-*.json 2>/dev/null | sort | tr '\n' ' ')

  if [ -n "$GLYPH_LIST" ]; then
    # Run composition --once
    if eval "$IMAGE_PIPELINE compose $GLYPH_LIST --output-phrase-image /tmp/rghw-m7-phrase.png --output-manifest /tmp/rghw-m7-manifest.json" 2>/tmp/rghw-m7-compose.log; then
      if [ -f /tmp/rghw-m7-phrase.png ]; then
        say "[ ok ] composition --once produced phrase PNG"
        # Verify PNG magic bytes
        if xxd -l 8 /tmp/rghw-m7-phrase.png 2>/dev/null | grep -q "8950 4e47 0d0a 1a0a"; then
          say "[ ok ] phrase PNG has valid PNG magic bytes"
        else
          FAILED=$((FAILED + 1))
          say "[FAIL] phrase PNG has invalid magic bytes"
        fi
        # Verify manifest was generated
        if [ -f /tmp/rghw-m7-manifest.json ]; then
          say "[ ok ] composition manifest generated"
        else
          FAILED=$((FAILED + 1))
          say "[FAIL] composition manifest missing"
        fi
      else
        FAILED=$((FAILED + 1))
        say "[FAIL] composition --once did not produce phrase PNG"
        cat /tmp/rghw-m7-compose.log
      fi

      # Verify determinism: run again, compare SHA-256 (both runs must succeed).
      COMPOSE2_OK=0
      eval "$IMAGE_PIPELINE compose $GLYPH_LIST --output-phrase-image /tmp/rghw-m7-phrase2.png --output-manifest /tmp/rghw-m7-manifest2.json" >/dev/null 2>&1 && COMPOSE2_OK=1
      SHA1=$(shasum -a 256 /tmp/rghw-m7-phrase.png 2>/dev/null | awk '{print $1}')
      SHA2=$(shasum -a 256 /tmp/rghw-m7-phrase2.png 2>/dev/null | awk '{print $1}')
      if [ "$COMPOSE2_OK" = 1 ] && [ -n "$SHA1" ] && [ "$SHA1" = "$SHA2" ]; then
        say "[ ok ] composition is deterministic (sha256 match)"
      else
        FAILED=$((FAILED + 1))
        say "[FAIL] composition is nondeterministic or second run failed (ok=$COMPOSE2_OK): $SHA1 != $SHA2"
      fi

      # Run preprocessing --once
      if eval "$IMAGE_PIPELINE preprocess --phrase-image /tmp/rghw-m7-phrase.png --composition-manifest /tmp/rghw-m7-manifest.json --output-ocr-image /tmp/rghw-m7-ocr.png --output-crops-dir /tmp/rghw-m7-crops --output-report /tmp/rghw-m7-report.json" 2>/tmp/rghw-m7-prep.log; then
        if [ -f /tmp/rghw-m7-ocr.png ]; then
          say "[ ok ] preprocessing --once produced OCR image"
          if [ -f /tmp/rghw-m7-report.json ]; then
            say "[ ok ] preprocessing report generated"
          else
            FAILED=$((FAILED + 1))
            say "[FAIL] preprocessing report missing"
          fi
          # Verify crops were generated
          # shellcheck disable=SC2012 # ls count for crops is safe, find would be verbose
          CROP_COUNT=$(ls /tmp/rghw-m7-crops/*.png 2>/dev/null | wc -l | tr -d ' ')
          if [ "$CROP_COUNT" -gt 0 ]; then
            say "[ ok ] position crops generated ($CROP_COUNT crops)"
          else
            FAILED=$((FAILED + 1))
            say "[FAIL] no position crops generated"
          fi
        else
          FAILED=$((FAILED + 1))
          say "[FAIL] preprocessing --once did not produce OCR image"
        fi
      else
        FAILED=$((FAILED + 1))
        say "[FAIL] preprocessing --once failed"
        cat /tmp/rghw-m7-prep.log
      fi

      rm -f /tmp/rghw-m7-phrase.png /tmp/rghw-m7-phrase2.png /tmp/rghw-m7-manifest.json /tmp/rghw-m7-manifest2.json /tmp/rghw-m7-ocr.png /tmp/rghw-m7-report.json /tmp/rghw-m7-compose.log /tmp/rghw-m7-prep.log
      rm -rf /tmp/rghw-m7-crops
    else
      FAILED=$((FAILED + 1))
      say "[FAIL] image-pipeline compose command failed"
    fi
  else
    FAILED=$((FAILED + 1))
    say "[FAIL] no glyph fixtures found"
  fi
  rm -rf "$M7_FIXTURES"
else
  skip "python3 or image-pipeline for M7 composition/preprocessing"
fi

echo ""
echo "Verifying Milestone 8 OCR and adjudication (--once):"

if command -v node >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
  M8_FIXTURES="/tmp/rghw-m8-fixtures"
  mkdir -p "$M8_FIXTURES/crops"

  python3 -c "
import struct, zlib
def make_png(width, height, fill=(128, 128, 128, 255), glyph=None):
    raw = b''
    for y in range(height):
        raw += b'\x00'
        for x in range(width):
            if glyph is not None and (x == 8 or x == width - 9 or (width // 2 - 4 <= x <= width // 2 + 4 and height // 4 <= y <= 3 * height // 4)):
                raw += bytes((20, 20, 20, 255))
            else:
                raw += bytes(fill)

    def chunk(ctype, data):
        c = ctype + data
        return struct.pack('>I', len(data)) + c + struct.pack('>I', zlib.crc32(c) & 0xffffffff)
    sig = b'\x89PNG\r\n\x1a\n'
    ihdr = struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0)
    idat = zlib.compress(raw)
    return sig + chunk(b'IHDR', ihdr) + chunk(b'IDAT', idat) + chunk(b'IEND', b'')

with open('$M8_FIXTURES/ocr-image.png', 'wb') as f:
    f.write(make_png(200, 100))

for pos in [0, 1, 2, 5]:
    if pos == 5:
        with open('$M8_FIXTURES/crops/crop-position-%d.png' % pos, 'wb') as f:
            f.write(make_png(50, 50))
    else:
        with open('$M8_FIXTURES/crops/crop-position-%d.png' % pos, 'wb') as f:
            f.write(make_png(50, 50, glyph='H'))

import json
manifest = {
    'layout': [
        {'position': 0, 'x': 0, 'y': 0, 'width': 50, 'height': 50, 'advanceWidth': 1.0, 'baseline': 40},
        {'position': 1, 'x': 60, 'y': 0, 'width': 50, 'height': 50, 'advanceWidth': 1.0, 'baseline': 40},
        {'position': 2, 'x': 120, 'y': 0, 'width': 50, 'height': 50, 'advanceWidth': 1.0, 'baseline': 40},
        {'position': 5, 'x': 180, 'y': 0, 'width': 0, 'height': 0, 'advanceWidth': 0.6, 'baseline': 0},
    ],
    'totalWidth': 200,
    'totalHeight': 100,
}
with open('$M8_FIXTURES/manifest.json', 'w') as f:
    json.dump(manifest, f)
print('M8 fixtures created')
"

  OCR_WORKER="$ROOT/services/ocr-worker-node/out/index.js"
  M8_RUNNER="$ROOT/services/ocr-worker-node/tests/m8-once-runner.js"
  if [ -f "$OCR_WORKER" ] && [ -f "$M8_RUNNER" ]; then
    if node "$M8_RUNNER" "$M8_FIXTURES" "$M8_FIXTURES/observations.json" "$M8_FIXTURES/ocr-event.json" 2>/tmp/rghw-m8-ocr.log; then
      say "[ ok ] OCR worker --once produced observations"
  if [ -f "$M8_FIXTURES/observations.json" ]; then
    say "[ ok ] observations file written"
    if [ -f "$M8_FIXTURES/ocr-event.json" ]; then
      if grep -q '"inputMaturity": 60' "$M8_FIXTURES/ocr-event.json" && grep -q '"outputMaturity": 70' "$M8_FIXTURES/ocr-event.json"; then
        say "[ ok ] OCR event mature 60 -> 70"
      else
        FAILED=$((FAILED + 1))
        say "[FAIL] OCR event missing maturity 60 -> 70"
      fi
    else
      FAILED=$((FAILED + 1))
      say "[FAIL] OCR event file missing"
    fi
  else
    FAILED=$((FAILED + 1))
    say "[FAIL] OCR observations file missing"
  fi
    else
      FAILED=$((FAILED + 1))
      say "[FAIL] OCR worker --once failed"
      cat /tmp/rghw-m8-ocr.log
    fi
  else
    skip "ocr-worker not built"
  fi

  if [ -f "$M8_FIXTURES/observations.json" ]; then
    if command -v ruby >/dev/null 2>&1; then
      if (cd "$ROOT/services/adjudicator-ruby" && ruby -Ilib -e "require 'json'; require 'adjudicator'; result = Adjudicator::AdjudicatorImpl.run_once('$M8_FIXTURES/observations.json', '$M8_FIXTURES/manifest.json', event_output_path: '$M8_FIXTURES/adjudicator-event.json'); puts JSON.pretty_generate(result)" > "$M8_FIXTURES/adjudicated.json" 2>/tmp/rghw-m8-adjudicator.log); then
        say "[ ok ] adjudicator --once produced adjudicated symbols"
        if [ -f "$M8_FIXTURES/adjudicated.json" ]; then
          say "[ ok ] adjudicated file written"
          if [ -f "$M8_FIXTURES/adjudicator-event.json" ]; then
            if grep -q '"inputMaturity": 70' "$M8_FIXTURES/adjudicator-event.json" && grep -q '"outputMaturity": 80' "$M8_FIXTURES/adjudicator-event.json"; then
              say "[ ok ] adjudicated event mature 70 -> 80"
            else
              FAILED=$((FAILED + 1))
              say "[FAIL] adjudicated event missing maturity 70 -> 80"
            fi
          else
            FAILED=$((FAILED + 1))
            say "[FAIL] adjudicator event file missing"
          fi
        else
          FAILED=$((FAILED + 1))
          say "[FAIL] adjudicated file missing"
        fi
      else
        FAILED=$((FAILED + 1))
        say "[FAIL] adjudicator --once failed"
        cat /tmp/rghw-m8-adjudicator.log
      fi
    else
      skip "ruby for adjudicator"
    fi
  fi

  rm -rf "$M8_FIXTURES"
else
  skip "node or python3 for M8 OCR/adjudication"
fi

echo ""
echo "Verifying Milestone 9 Rust assembly (--once):"

if [ -x "$ROOT/services/phrase-assembler-rust/target/debug/phrase-assembler" ]; then
  M9_FIXTURES="/tmp/rghw-m9-fixtures"
  mkdir -p "$M9_FIXTURES"
  python3 -c "
import json, os
out = '$M9_FIXTURES/tokens.json'
tokens = []
for pos in range(11):
    if pos == 5:
        tok = {'position': 5, 'tokenType': 'Gap', 'utf8': ' ', 'confidence': 0.99, 'inputArtifact': 'evidence-gap-5', 'run_id': 'run-123'}
    else:
        ch = 'HELLO WORLD'[pos]
        tok = {'position': pos, 'tokenType': 'Symbol', 'utf8': ch, 'confidence': 0.95, 'inputArtifact': f'evidence-{pos}', 'run_id': 'run-123'}
    tokens.append(tok)
with open(out, 'w') as f:
    json.dump(tokens, f)
print('M9 fixtures created')
"
  PHRASE_BIN="$ROOT/services/phrase-assembler-rust/target/debug/phrase-assembler"
  if "$PHRASE_BIN" --once --input="$M9_FIXTURES/tokens.json" --output="$M9_FIXTURES/manifest.json" --event-output="$M9_FIXTURES/event.json" 2>/tmp/rghw-m9.log; then
    # shellcheck disable=SC2034,SC2002 # ASSEMBLED used for debug, cat is intentional for fallback
    ASSEMBLED=$(cat "$M9_FIXTURES/manifest.json" | python3 -c "import json,sys; m=json.load(open(sys.argv[1])); print(m.get('sha256',''))" "$M9_FIXTURES/manifest.json" 2>/dev/null || echo "")
    # shellcheck disable=SC2034 # TEXT retained for debug output
    TEXT=$(python3 -c "import json; print(open('$M9_FIXTURES/manifest.json').read()[:200])" 2>/dev/null)
    # manifest exists
    if [ -f "$M9_FIXTURES/manifest.json" ]; then
      say "[ ok ] phrase-assembler --once produced manifest"
    else
      FAILED=$((FAILED + 1))
      say "[FAIL] phrase-assembler manifest missing"
    fi
    if [ -f "$M9_FIXTURES/event.json" ]; then
      if grep -q '"inputMaturity": 80' "$M9_FIXTURES/event.json" && grep -q '"outputMaturity": 90' "$M9_FIXTURES/event.json"; then
        say "[ ok ] phrase-assembled event mature 80 -> 90"
      else
        FAILED=$((FAILED + 1))
        say "[FAIL] phrase-assembled event missing maturity 80 -> 90"
      fi
      if grep -q '"assembledText": "HELLO WORLD"' "$M9_FIXTURES/event.json"; then
        say "[ ok ] phrase-assembled text HELLO WORLD"
      else
        FAILED=$((FAILED + 1))
        # shellcheck disable=SC2002 # cat is readable for small JSON snippet
        say "[FAIL] phrase-assembled text wrong: $(cat "$M9_FIXTURES/event.json" | head -n 5)"
      fi
      for field in message targetText expectedCharacter unicodeCodePoint characterName glyphLabel; do
        if grep -q "\"$field\"" "$M9_FIXTURES/event.json"; then
          FAILED=$((FAILED + 1))
          say "[FAIL] prohibited field '\$field' present in phrase-assembled event"
        fi
      done
      say "[ ok ] no prohibited fields in phrase-assembled event"
      # determinism
      M9_RUN2_OK=0
      "$PHRASE_BIN" --once --input="$M9_FIXTURES/tokens.json" --output="$M9_FIXTURES/manifest2.json" --event-output="$M9_FIXTURES/event2.json" >/dev/null 2>&1 && M9_RUN2_OK=1
      if [ "$M9_RUN2_OK" = 1 ] && cmp -s "$M9_FIXTURES/manifest.json" "$M9_FIXTURES/manifest2.json"; then
        say "[ ok ] phrase-assembler --once deterministic"
      else
        FAILED=$((FAILED + 1))
        say "[FAIL] phrase-assembler --once nondeterministic or second run failed (ok=$M9_RUN2_OK)"
      fi
    else
      FAILED=$((FAILED + 1))
      say "[FAIL] phrase-assembler event missing"
    fi
    # duplicate/missing rejection is covered by unit tests
  else
    FAILED=$((FAILED + 1))
    say "[FAIL] phrase-assembler --once failed"
    cat /tmp/rghw-m9.log
  fi
  rm -rf "$M9_FIXTURES"
else
  skip "phrase-assembler binary for M9"
fi

echo ""
echo "Integration results: failures=$FAILED skipped=$SKIPPED"
if [ "$FAILED" -gt 0 ]; then
  echo "integration: FAIL"
  exit 1
fi
echo "integration: OK"
