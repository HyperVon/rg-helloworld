#!/usr/bin/env bash
# Regenerate the C# gRPC server code from the rasterizer proto contract.
#
# Grpc.Tools ships no macOS-arm64 protoc/grpc_csharp_plugin, so on arm64
# macOS the codegen runs in the pinned .NET SDK container; on x86_64 Linux
# (CI) it runs natively with the pinned protoc plus the plugin extracted
# from the pinned Grpc.Tools package. Output is committed under
# services/rasterizer-dotnet/generated/ and is never hand-edited.
#
# Usage:
#   scripts/gen-csharp-proto.sh            regenerate in place
#   scripts/gen-csharp-proto.sh --check    fail if regeneration changes files
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK=0
if [[ "${1:-}" == "--check" ]]; then
    CHECK=1
fi

pin() {
    grep -E "^${1}=" "$ROOT/versions.env" | head -1 | cut -d= -f2-
}

GRPC_TOOLS_VERSION="$(pin GRPC_TOOLS_VERSION)"
DOTNET_SDK_IMAGE="mcr.microsoft.com/dotnet/sdk:$(pin DOTNET_SDK_IMAGE_VERSION)"
OUT_DIR="$ROOT/services/rasterizer-dotnet/generated"
PROTO="$ROOT/contracts/proto/rasterizer/v1/rasterizer.proto"

if [ "$CHECK" -eq 1 ]; then
    BEFORE="$(find "$OUT_DIR" -type f -name '*.cs' | sort | xargs shasum -a 256 2>/dev/null || true)"
fi

case "$(uname -s)-$(uname -m)" in
    Linux-x86_64)
        TOOLS="$ROOT/.local/tools"
        PROTOC_DIR="$TOOLS/protoc-$(pin PROTOC_VERSION)"
        PROTOC="$PROTOC_DIR/bin/protoc"
        if [ ! -x "$PROTOC" ]; then
            bash "$ROOT/scripts/gen-proto.sh" >/dev/null
        fi
        PLUGIN_DIR="$TOOLS/grpc.tools-${GRPC_TOOLS_VERSION}"
        if [ ! -x "$PLUGIN_DIR/grpc_csharp_plugin" ]; then
            mkdir -p "$PLUGIN_DIR"
            curl -fsSL --retry 3 \
                "https://api.nuget.org/v3-flatcontainer/grpc.tools/${GRPC_TOOLS_VERSION}/grpc.tools.${GRPC_TOOLS_VERSION}.nupkg" \
                -o "$TOOLS/grpc.tools.${GRPC_TOOLS_VERSION}.nupkg"
            unzip -q -o "$TOOLS/grpc.tools.${GRPC_TOOLS_VERSION}.nupkg" \
                "tools/linux_x64/grpc_csharp_plugin" -d "$PLUGIN_DIR"
            chmod +x "$PLUGIN_DIR/tools/linux_x64/grpc_csharp_plugin"
            rm -f "$TOOLS/grpc.tools.${GRPC_TOOLS_VERSION}.nupkg"
        fi
        PLUGIN="$PLUGIN_DIR/tools/linux_x64/grpc_csharp_plugin"
        mkdir -p "$OUT_DIR"
        "$PROTOC" -I "$ROOT/contracts/proto" \
            --csharp_out="$OUT_DIR" \
            --grpc_out="$OUT_DIR" \
            --plugin=protoc-gen-grpc="$PLUGIN" \
            "$PROTO"
        ;;
    Darwin-arm64)
        mkdir -p "$OUT_DIR"
        chmod -R u+w "$OUT_DIR"
        docker run --rm \
            -v "$ROOT:/src" \
            -e GRPC_TOOLS_VERSION="$GRPC_TOOLS_VERSION" \
            -e OUT=/src/services/rasterizer-dotnet/generated \
            -e PROTO=/src/contracts/proto/rasterizer/v1/rasterizer.proto \
            "$DOTNET_SDK_IMAGE" \
            bash -c '
                set -euo pipefail
                ARCH=$(uname -m)
                case "$ARCH" in
                    aarch64|arm64) TOOLDIR=linux_arm64 ;;
                    x86_64|amd64) TOOLDIR=linux_x64 ;;
                    *) echo "unsupported container arch $ARCH" >&2; exit 1 ;;
                esac
                mkdir -p /tmp/gen && cd /tmp/gen
                dotnet new console -o . --force >/dev/null
                dotnet add package Grpc.Tools --version "$GRPC_TOOLS_VERSION" >/dev/null
                NUGET="$HOME/.nuget/packages/grpc.tools/$GRPC_TOOLS_VERSION/tools/$TOOLDIR"
                "$NUGET/protoc" -I /src/contracts/proto \
                    --csharp_out="$OUT" \
                    --grpc_out="$OUT" \
                    --plugin=protoc-gen-grpc="$NUGET/grpc_csharp_plugin" \
                    "$PROTO"
            '
        ;;
    *)
        echo "gen-csharp-proto: unsupported platform $(uname -s)-$(uname -m)" >&2
        exit 1
        ;;
esac

if [ "$CHECK" -eq 1 ]; then
    AFTER="$(find "$OUT_DIR" -type f -name '*.cs' | sort | xargs shasum -a 256 2>/dev/null || true)"
    if [ "$BEFORE" != "$AFTER" ]; then
        echo "gen-csharp-proto: generated C# code is out of date; run scripts/gen-csharp-proto.sh" >&2
        exit 1
    fi
    echo ">> C# gRPC code is up to date"
fi
