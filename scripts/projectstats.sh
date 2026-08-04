/bin/bash <<'BASH'
set -u

ROOT="."
STATS_FILE="$(mktemp -t source-stats)"
trap 'rm -f "$STATS_FILE"' EXIT

# Directories commonly containing dependencies, generated code, caches,
# compiled output, IDE metadata, or build artifacts.
find_project() {
  find "$ROOT" \
    \( -type d \( \
      -name .git -o \
      -name .svn -o \
      -name .hg -o \
      -name node_modules -o \
      -name vendor -o \
      -name Pods -o \
      -name build -o \
      -name dist -o \
      -name target -o \
      -name out -o \
      -name bin -o \
      -name obj -o \
      -name coverage -o \
      -name .coverage -o \
      -name .gradle -o \
      -name .idea -o \
      -name .vscode -o \
      -name .next -o \
      -name .nuxt -o \
      -name .output -o \
      -name .cache -o \
      -name .parcel-cache -o \
      -name .turbo -o \
      -name .terraform -o \
      -name .venv -o \
      -name venv -o \
      -name __pycache__ -o \
      -name .pytest_cache -o \
      -name .mypy_cache -o \
      -name .ruff_cache -o \
      -name DerivedData -o \
      -name 'cmake-build-*' -o \
      -name 'bazel-*' \
    \) -prune \) -o "$@"
}

directory_count="$(
  find_project -type d -print |
    awk 'END { print (NR > 0 ? NR - 1 : 0) }'
)"

all_file_count="$(
  find_project -type f -print |
    awk 'END { print NR + 0 }'
)"

while IFS= read -r -d '' file; do
  filename="${file##*/}"
  type=""

  # Handle important source/build files that do not have normal extensions.
  case "$filename" in
    Makefile|makefile|GNUmakefile)
      type="Makefile"
      ;;
    Dockerfile|Dockerfile.*)
      type="Dockerfile"
      ;;
    CMakeLists.txt)
      type="CMake"
      ;;
    BUILD|BUILD.bazel|WORKSPACE|WORKSPACE.bazel|MODULE.bazel)
      type="Bazel"
      ;;
    Rakefile)
      type="Rakefile"
      ;;
    Gemfile)
      type="Gemfile"
      ;;
    *)
      if [[ "$filename" == *.* ]]; then
        extension="${filename##*.}"
        extension="$(
          printf '%s' "$extension" |
            tr '[:upper:]' '[:lower:]'
        )"

        case "$extension" in
          c|h|cc|cpp|cxx|hh|hpp|hxx|m|mm|swift|metal|\
          java|kt|kts|scala|sc|groovy|gradle|clj|cljs|cljc|edn|\
          go|rs|zig|nim|\
          cs|fs|fsx|fsi|vb|\
          py|pyw|pyx|pxd|r|jl|lua|pl|pm|tcl|\
          rb|erb|php|ex|exs|erl|hrl|hs|lhs|ml|mli|\
          js|jsx|mjs|cjs|ts|tsx|mts|cts|vue|svelte|astro|\
          sh|bash|zsh|fish|ps1|bat|cmd|\
          html|htm|css|scss|sass|less|styl|\
          sql|graphql|gql|proto|thrift|sol|dart|\
          asm|s|v|vhd|vhdl|sv|svh|\
          xml|xsl|xslt|yaml|yml|toml)
            type=".$extension"
            ;;
        esac
      else
        # Include extensionless executable scripts with a shebang.
        first_line="$(head -n 1 "$file" 2>/dev/null || true)"
        case "$first_line" in
          '#!'*)
            type="[shebang script]"
            ;;
        esac
      fi
      ;;
  esac

  [[ -n "$type" ]] || continue

  # awk's NR counts the final line even when it has no trailing newline.
  line_count="$(awk 'END { print NR + 0 }' "$file" 2>/dev/null || printf '0')"
  printf '%s\t%s\n' "$type" "$line_count" >> "$STATS_FILE"
done < <(find_project -type f -print0)

source_file_count="$(awk 'END { print NR + 0 }' "$STATS_FILE")"
file_type_count="$(cut -f1 "$STATS_FILE" | sort -u | awk 'END { print NR + 0 }')"
total_source_lines="$(awk -F '\t' '{ total += $2 } END { print total + 0 }' "$STATS_FILE")"

printf '\nProject source statistics\n'
printf '%s\n' '========================='
printf 'Directories:          %d\n' "$directory_count"
printf 'All project files:    %d\n' "$all_file_count"
printf 'Source files:         %d\n' "$source_file_count"
printf 'Source file types:    %d\n' "$file_type_count"
printf 'Total source lines:   %d\n\n' "$total_source_lines"

awk -F '\t' '
  {
    files[$1]++
    lines[$1] += $2
  }
  END {
    for (type in files) {
      printf "%s\t%d\t%d\n", type, files[type], lines[type]
    }
  }
' "$STATS_FILE" |
  sort -t $'\t' -k3,3nr |
  awk -F '\t' '
    BEGIN {
      printf "%-22s %10s %15s\n", "FILE TYPE", "FILES", "LINES"
      printf "%-22s %10s %15s\n", "---------", "-----", "-----"
    }
    {
      printf "%-22s %10d %15d\n", $1, $2, $3
    }
  '

printf '\n'
BASH
