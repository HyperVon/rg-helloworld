#!/usr/bin/env bash
# Regenerate the Go gRPC client from the rasterizer proto contract.
#
# The proto contract at contracts/proto/rasterizer/v1/rasterizer.proto is the
# single source of truth; generated code is never hand-edited. protoc and the
# Go plugins are pinned in versions.env; protoc is downloaded into .local/
# (git-ignored) on first use. The C# side generates at build time via
# Grpc.Tools and needs no host protoc.
#
# Usage:
#   scripts/gen-proto.sh            regenerate in place
#   scripts/gen-proto.sh --check    fail if regeneration changes files
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK=0
if [[ "${1:-}" == "--check" ]]; then
    CHECK=1
fi

pin() {
    grep -E "^${1}=" "$ROOT/versions.env" | head -1 | cut -d= -f2-
}

PROTOC_VERSION="$(pin PROTOC_VERSION)"
PROTOC_GEN_GO_VERSION="$(pin PROTOC_GEN_GO_VERSION)"
PROTOC_GEN_GO_GRPC_VERSION="$(pin PROTOC_GEN_GO_GRPC_VERSION)"

case "$(uname -s)-$(uname -m)" in
    Darwin-arm64) ASSET="protoc-${PROTOC_VERSION}-osx-aarch_64.zip" ;;
    Darwin-x86_64) ASSET="protoc-${PROTOC_VERSION}-osx-x86_64.zip" ;;
    Linux-x86_64) ASSET="protoc-${PROTOC_VERSION}-linux-x86_64.zip" ;;
    Linux-aarch64) ASSET="protoc-${PROTOC_VERSION}-linux-aarch_64.zip" ;;
    *)
        echo "gen-proto: unsupported platform $(uname -s)-$(uname -m)" >&2
        exit 1
        ;;
esac

TOOLS="$ROOT/.local/tools"
PROTOC_DIR="$TOOLS/protoc-${PROTOC_VERSION}"
PROTOC="$PROTOC_DIR/bin/protoc"

if [ ! -x "$PROTOC" ]; then
    echo ">> Downloading protoc ${PROTOC_VERSION} (${ASSET})"
    mkdir -p "$TOOLS"
    ZIP="$TOOLS/$ASSET"
    URL="https://github.com/protocolbuffers/protobuf/releases/download/v${PROTOC_VERSION}/${ASSET}"
    curl -fsSL --retry 3 -o "$ZIP" "$URL"
    rm -rf "$PROTOC_DIR"
    unzip -q "$ZIP" -d "$PROTOC_DIR"
    rm -f "$ZIP"
fi

GOBIN="$ROOT/.local/bin"
export GOBIN
echo ">> Installing protoc-gen-go ${PROTOC_GEN_GO_VERSION}"
go install "google.golang.org/protobuf/cmd/protoc-gen-go@${PROTOC_GEN_GO_VERSION}"
echo ">> Installing protoc-gen-go-grpc ${PROTOC_GEN_GO_GRPC_VERSION}"
go install "google.golang.org/grpc/cmd/protoc-gen-go-grpc@${PROTOC_GEN_GO_GRPC_VERSION}"

OUT_DIR="$ROOT/services/vector-normalizer-go/internal/rasterproto"
if [ "$CHECK" -eq 1 ]; then
    BEFORE="$(find "$OUT_DIR" -type f -name '*.go' | sort | xargs shasum -a 256 2>/dev/null || true)"
fi

PATH="$GOBIN:$PATH" "$PROTOC" \
    --go_out="$ROOT/services/vector-normalizer-go" \
    --go_opt=module=rghw.dev/vector-normalizer \
    --go-grpc_out="$ROOT/services/vector-normalizer-go" \
    --go-grpc_opt=module=rghw.dev/vector-normalizer \
    -I "$ROOT/contracts/proto" \
    "$ROOT/contracts/proto/rasterizer/v1/rasterizer.proto"

if [ "$CHECK" -eq 1 ]; then
    AFTER="$(find "$OUT_DIR" -type f -name '*.go' | sort | xargs shasum -a 256 2>/dev/null || true)"
    if [ "$BEFORE" != "$AFTER" ]; then
        echo "gen-proto: generated Go client is out of date; run scripts/gen-proto.sh" >&2
        exit 1
    fi
    echo ">> Go gRPC client is up to date"
fi
