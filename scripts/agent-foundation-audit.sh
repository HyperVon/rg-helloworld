#!/bin/sh
set -eu

script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd)
repo_dir=$(CDPATH= cd "$script_dir/.." && pwd)

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  echo "usage: $0 FOUNDATION_ROOT [OUTPUT_DIR]" >&2
  exit 2
fi

foundation_root=$(CDPATH= cd "$1" 2>/dev/null && pwd) || {
  echo "foundation root is not readable: $1" >&2
  exit 2
}
foundation="$foundation_root/bin/agent-foundation"

if [ ! -x "$foundation" ]; then
  echo "foundation shell entry point not found or not executable: $foundation" >&2
  exit 2
fi

if [ "$#" -eq 2 ]; then
  output_dir=$2
  case "$output_dir" in
    /*) ;;
    *) output_dir="$repo_dir/$output_dir" ;;
  esac
  mkdir -p "$output_dir"
else
  output_dir=$(mktemp -d "${TMPDIR:-/tmp}/rghw-agent-foundation.XXXXXX")
fi

"$foundation" inventory "$repo_dir" --output "$output_dir/inventory.json"
"$foundation" scan "$repo_dir" --output "$output_dir/scan.json"

echo "Foundation audit completed: $output_dir"
echo "Inventory: $output_dir/inventory.json"
echo "Scan: $output_dir/scan.json"
