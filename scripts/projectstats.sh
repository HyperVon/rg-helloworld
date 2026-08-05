#!/usr/bin/env bash

set -u
set -o pipefail

ROOT="."
SHOW_FILES=0
SHOW_BINARY=0

usage() {
  cat <<'EOF'
Usage: projectstats.sh [OPTIONS] [ROOT]

Count directories, files, text-file types, and lines while ignoring common
build, dependency, cache, and IDE directories.

Options:
  --show-files    List every counted text file and its line count
  --show-binary   List files classified as binary
  -h, --help      Show this help

Examples:
  ./scripts/projectstats.sh
  ./scripts/projectstats.sh /path/to/project
  ./scripts/projectstats.sh --show-files .
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --show-files)
      SHOW_FILES=1
      ;;
    --show-binary)
      SHOW_BINARY=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift

      if [ "$#" -gt 0 ]; then
        ROOT="$1"
        shift
      fi

      break
      ;;
    -*)
      printf 'Unknown option: %s\n\n' "$1" >&2
      usage >&2
      exit 2
      ;;
    *)
      ROOT="$1"
      ;;
  esac

  shift
done

if [ ! -d "$ROOT" ]; then
  printf 'Error: directory does not exist: %s\n' "$ROOT" >&2
  exit 2
fi

STATS_FILE="$(mktemp -t project-source-stats)"
UNKNOWN_FILE="$(mktemp -t project-unknown-text)"
BINARY_FILE="$(mktemp -t project-binary-files)"

cleanup() {
  rm -f "$STATS_FILE" "$UNKNOWN_FILE" "$BINARY_FILE"
}

trap cleanup EXIT INT TERM

# Run find while pruning dependencies, caches, generated outputs,
# IDE metadata, compiled artifacts, and local infrastructure state.
find_project() {
  find "$ROOT" \
    \( -type d \( \
      -name .git -o \
      -name .svn -o \
      -name .hg -o \
      -name node_modules -o \
      -name bower_components -o \
      -name jspm_packages -o \
      -name vendor -o \
      -name Pods -o \
      -name .bundle -o \
      -name build -o \
      -name builds -o \
      -name dist -o \
      -name target -o \
      -name out -o \
      -name outputs -o \
      -name bin -o \
      -name obj -o \
      -name coverage -o \
      -name .coverage -o \
      -name htmlcov -o \
      -name .nyc_output -o \
      -name test-results -o \
      -name .gradle -o \
      -name .mvn -o \
      -name .idea -o \
      -name .vscode -o \
      -name .vs -o \
      -name .fleet -o \
      -name .next -o \
      -name .nuxt -o \
      -name .output -o \
      -name .svelte-kit -o \
      -name .angular -o \
      -name .vite -o \
      -name .cache -o \
      -name .parcel-cache -o \
      -name .turbo -o \
      -name .nx -o \
      -name .terraform -o \
      -name .terragrunt-cache -o \
      -name .serverless -o \
      -name .aws-sam -o \
      -name .venv -o \
      -name venv -o \
      -name __pycache__ -o \
      -name .pytest_cache -o \
      -name .mypy_cache -o \
      -name .ruff_cache -o \
      -name .tox -o \
      -name .nox -o \
      -name .hypothesis -o \
      -name .ipynb_checkpoints -o \
      -name .cargo -o \
      -name .rustup -o \
      -name DerivedData -o \
      -name .dart_tool -o \
      -name .pub-cache -o \
      -name .kotlin -o \
      -name .scannerwork -o \
      -name .sonar -o \
      -name .local -o \
      -name tmp -o \
      -name temp -o \
      -name logs -o \
      -name 'cmake-build-*' -o \
      -name 'bazel-*' -o \
      -name buck-out \
    \) -prune \) -o "$@"
}

# Skip generated, compiled, state, log, and minified files that may exist
# outside the ignored directories.
should_skip_file() {
  local filename="${1##*/}"

  case "$filename" in
    .DS_Store|Thumbs.db|desktop.ini|\
    '*.class'|'*.jar'|'*.war'|'*.ear'|\
    '*.o'|'*.obj'|'*.a'|'*.so'|'*.dylib'|'*.dll'|'*.exe'|\
    '*.pyc'|'*.pyo'|\
    '*.min.js'|'*.min.css'|'*.map'|\
    '*.tfstate'|'*.tfstate.backup'|\
    '*.log')
      return 0
      ;;
  esac

  return 1
}

# Determine whether a file is textual.
#
# First use the MIME type reported by macOS's file command, then fall back
# to grep's binary detection for text formats reported as application/octet-stream.
is_text_file() {
  local file_path="$1"
  local mime_type

  [ ! -s "$file_path" ] && return 0

  mime_type="$(file -b --mime-type "$file_path" 2>/dev/null || true)"

  case "$mime_type" in
    text/*|\
    application/json|\
    application/ld+json|\
    application/xml|\
    application/yaml|\
    application/x-yaml|\
    application/toml|\
    application/javascript|\
    application/x-javascript|\
    application/sql|\
    application/graphql|\
    application/x-httpd-php|\
    application/x-shellscript|\
    application/x-perl|\
    application/x-ruby|\
    application/x-python|\
    application/x-empty)
      return 0
      ;;
  esac

  LC_ALL=C grep -Iq . "$file_path" 2>/dev/null
}

classify_file() {
  local file_path="$1"
  local filename="${file_path##*/}"
  local lower
  local extension
  local first_line

  lower="$(
    printf '%s' "$filename" |
      tr '[:upper:]' '[:lower:]'
  )"

  # Important exact filenames.
  case "$filename" in
    Makefile|makefile|GNUmakefile)
      printf '%s' 'Makefile'
      return
      ;;
    Dockerfile|Dockerfile.*|*.Dockerfile)
      printf '%s' 'Dockerfile'
      return
      ;;
    CMakeLists.txt)
      printf '%s' 'CMake'
      return
      ;;
    BUILD|BUILD.bazel|WORKSPACE|WORKSPACE.bazel|MODULE.bazel)
      printf '%s' 'Bazel'
      return
      ;;
    Rakefile)
      printf '%s' 'Rakefile'
      return
      ;;
    Gemfile)
      printf '%s' 'Gemfile'
      return
      ;;
    Gemfile.lock)
      printf '%s' 'Ruby lockfile'
      return
      ;;
    Cargo.toml)
      printf '%s' 'Cargo manifest'
      return
      ;;
    Cargo.lock)
      printf '%s' 'Cargo lockfile'
      return
      ;;
    go.mod)
      printf '%s' 'Go module'
      return
      ;;
    go.sum)
      printf '%s' 'Go checksums'
      return
      ;;
    package.json)
      printf '%s' 'Node package manifest'
      return
      ;;
    package-lock.json|npm-shrinkwrap.json)
      printf '%s' 'npm lockfile'
      return
      ;;
    yarn.lock)
      printf '%s' 'Yarn lockfile'
      return
      ;;
    pnpm-lock.yaml)
      printf '%s' 'pnpm lockfile'
      return
      ;;
    composer.json)
      printf '%s' 'Composer manifest'
      return
      ;;
    composer.lock)
      printf '%s' 'Composer lockfile'
      return
      ;;
    requirements.txt|requirements-*.txt)
      printf '%s' 'Python requirements'
      return
      ;;
    Pipfile)
      printf '%s' 'Pipenv manifest'
      return
      ;;
    Pipfile.lock)
      printf '%s' 'Pipenv lockfile'
      return
      ;;
    poetry.lock)
      printf '%s' 'Poetry lockfile'
      return
      ;;
    pyproject.toml)
      printf '%s' 'Python project'
      return
      ;;
    setup.py|setup.cfg)
      printf '%s' 'Python packaging'
      return
      ;;
    tox.ini)
      printf '%s' 'Tox configuration'
      return
      ;;
    gradlew)
      printf '%s' 'Gradle wrapper'
      return
      ;;
    gradlew.bat)
      printf '%s' 'Gradle wrapper batch'
      return
      ;;
    settings.gradle|settings.gradle.kts)
      printf '%s' 'Gradle settings'
      return
      ;;
    build.gradle|build.gradle.kts)
      printf '%s' 'Gradle build'
      return
      ;;
    gradle.properties)
      printf '%s' 'Gradle properties'
      return
      ;;
    mvnw)
      printf '%s' 'Maven wrapper'
      return
      ;;
    mvnw.cmd)
      printf '%s' 'Maven wrapper batch'
      return
      ;;
    pom.xml)
      printf '%s' 'Maven POM'
      return
      ;;
    Directory.Build.props|Directory.Build.targets|Directory.Packages.props)
      printf '%s' '.NET build configuration'
      return
      ;;
    global.json)
      printf '%s' '.NET SDK configuration'
      return
      ;;
    NuGet.config|nuget.config)
      printf '%s' 'NuGet configuration'
      return
      ;;
    Chart.yaml|Chart.yml)
      printf '%s' 'Helm chart'
      return
      ;;
    values.yaml|values.yml|values-*.yaml|values-*.yml)
      printf '%s' 'Helm values'
      return
      ;;
    kustomization.yaml|kustomization.yml|Kustomization)
      printf '%s' 'Kustomize'
      return
      ;;
    docker-compose.yml|docker-compose.yaml|compose.yml|compose.yaml)
      printf '%s' 'Docker Compose'
      return
      ;;
    buf.yaml|buf.gen.yaml|buf.work.yaml)
      printf '%s' 'Buf configuration'
      return
      ;;
    Procfile)
      printf '%s' 'Procfile'
      return
      ;;
    Vagrantfile)
      printf '%s' 'Vagrantfile'
      return
      ;;
    Brewfile)
      printf '%s' 'Brewfile'
      return
      ;;
    Justfile|justfile)
      printf '%s' 'Justfile'
      return
      ;;
    Taskfile.yml|Taskfile.yaml)
      printf '%s' 'Taskfile'
      return
      ;;
    Jenkinsfile|Jenkinsfile.*)
      printf '%s' 'Jenkinsfile'
      return
      ;;
    Tiltfile)
      printf '%s' 'Tiltfile'
      return
      ;;
    Earthfile)
      printf '%s' 'Earthfile'
      return
      ;;
    CODEOWNERS)
      printf '%s' 'CODEOWNERS'
      return
      ;;
    LICENSE|LICENSE.*|COPYING|COPYING.*|NOTICE|NOTICE.*)
      printf '%s' 'License/notice'
      return
      ;;
    .env|.env.*)
      printf '%s' 'Environment file'
      return
      ;;
    .gitignore|.dockerignore|.helmignore|.npmignore|\
    .eslintignore|.prettierignore|.stylelintignore)
      printf '%s' 'Ignore file'
      return
      ;;
    .editorconfig)
      printf '%s' 'EditorConfig'
      return
      ;;
    .gitattributes)
      printf '%s' 'Git attributes'
      return
      ;;
    .gitmodules)
      printf '%s' 'Git modules'
      return
      ;;
    .tool-versions)
      printf '%s' 'Tool versions'
      return
      ;;
  esac

  # Compound suffixes must be checked before the final extension.
  case "$lower" in
    *.schema.json)
      printf '%s' 'JSON Schema'
      return
      ;;
    *.openapi.json|*.openapi.yaml|*.openapi.yml)
      printf '%s' 'OpenAPI'
      return
      ;;
    *.asyncapi.json|*.asyncapi.yaml|*.asyncapi.yml)
      printf '%s' 'AsyncAPI'
      return
      ;;
    *.gradle.kts)
      printf '%s' 'Gradle Kotlin'
      return
      ;;
    *.test.js|*.spec.js)
      printf '%s' 'JavaScript test'
      return
      ;;
    *.test.jsx|*.spec.jsx)
      printf '%s' 'JSX test'
      return
      ;;
    *.test.ts|*.spec.ts)
      printf '%s' 'TypeScript test'
      return
      ;;
    *.test.tsx|*.spec.tsx)
      printf '%s' 'TSX test'
      return
      ;;
    *.stories.js)
      printf '%s' 'JavaScript Storybook'
      return
      ;;
    *.stories.ts)
      printf '%s' 'TypeScript Storybook'
      return
      ;;
    *.stories.tsx)
      printf '%s' 'TSX Storybook'
      return
      ;;
    *.d.ts)
      printf '%s' 'TypeScript declaration'
      return
      ;;
    *.module.css)
      printf '%s' 'CSS module'
      return
      ;;
    *.module.scss)
      printf '%s' 'SCSS module'
      return
      ;;
    *.module.sass)
      printf '%s' 'Sass module'
      return
      ;;
    *.tfvars.json)
      printf '%s' 'Terraform variables JSON'
      return
      ;;
    *.tf.json)
      printf '%s' 'Terraform JSON'
      return
      ;;
    *.blade.php)
      printf '%s' 'Blade template'
      return
      ;;
    *.component.html)
      printf '%s' 'Angular template'
      return
      ;;
    *.component.scss)
      printf '%s' 'Angular SCSS'
      return
      ;;
    *.component.css)
      printf '%s' 'Angular CSS'
      return
      ;;
  esac

  if [[ "$filename" == *.* ]]; then
    extension="${filename##*.}"

    extension="$(
      printf '%s' "$extension" |
        tr '[:upper:]' '[:lower:]'
    )"

    case "$extension" in
      c)
        printf '%s' 'C'
        ;;
      h)
        printf '%s' 'C/C++ header'
        ;;
      cc|cpp|cxx)
        printf '%s' 'C++'
        ;;
      hh|hpp|hxx|ipp|tpp)
        printf '%s' 'C++ header'
        ;;
      m)
        printf '%s' 'Objective-C'
        ;;
      mm)
        printf '%s' 'Objective-C++'
        ;;
      swift)
        printf '%s' 'Swift'
        ;;
      metal)
        printf '%s' 'Metal'
        ;;
      cu)
        printf '%s' 'CUDA'
        ;;
      cuh)
        printf '%s' 'CUDA header'
        ;;
      cl)
        printf '%s' 'OpenCL'
        ;;

      java)
        printf '%s' 'Java'
        ;;
      kt)
        printf '%s' 'Kotlin'
        ;;
      kts)
        printf '%s' 'Kotlin script'
        ;;
      scala|sc)
        printf '%s' 'Scala'
        ;;
      groovy)
        printf '%s' 'Groovy'
        ;;
      gradle)
        printf '%s' 'Gradle'
        ;;
      clj)
        printf '%s' 'Clojure'
        ;;
      cljs)
        printf '%s' 'ClojureScript'
        ;;
      cljc)
        printf '%s' 'Clojure common'
        ;;
      edn)
        printf '%s' 'EDN'
        ;;

      go)
        printf '%s' 'Go'
        ;;
      rs)
        printf '%s' 'Rust'
        ;;
      zig)
        printf '%s' 'Zig'
        ;;
      nim)
        printf '%s' 'Nim'
        ;;

      cs)
        printf '%s' 'C#'
        ;;
      csx)
        printf '%s' 'C# script'
        ;;
      fs)
        printf '%s' 'F#'
        ;;
      fsx)
        printf '%s' 'F# script'
        ;;
      fsi)
        printf '%s' 'F# signature'
        ;;
      vb)
        printf '%s' 'Visual Basic'
        ;;
      csproj)
        printf '%s' 'C# project'
        ;;
      fsproj)
        printf '%s' 'F# project'
        ;;
      vbproj)
        printf '%s' 'Visual Basic project'
        ;;
      vcxproj)
        printf '%s' 'Visual C++ project'
        ;;
      sln)
        printf '%s' '.NET solution'
        ;;
      props|targets)
        printf '%s' 'MSBuild'
        ;;

      py)
        printf '%s' 'Python'
        ;;
      pyw)
        printf '%s' 'Python GUI'
        ;;
      pyi)
        printf '%s' 'Python type stub'
        ;;
      pyx)
        printf '%s' 'Cython'
        ;;
      pxd)
        printf '%s' 'Cython declaration'
        ;;
      ipynb)
        printf '%s' 'Jupyter notebook'
        ;;
      r)
        printf '%s' 'R'
        ;;
      rmd)
        printf '%s' 'R Markdown'
        ;;
      qmd)
        printf '%s' 'Quarto'
        ;;
      jl)
        printf '%s' 'Julia'
        ;;

      lua)
        printf '%s' 'Lua'
        ;;
      pl)
        printf '%s' 'Perl'
        ;;
      pm)
        printf '%s' 'Perl module'
        ;;
      tcl)
        printf '%s' 'Tcl'
        ;;
      rb)
        printf '%s' 'Ruby'
        ;;
      erb)
        printf '%s' 'ERB template'
        ;;
      php)
        printf '%s' 'PHP'
        ;;
      ex)
        printf '%s' 'Elixir'
        ;;
      exs)
        printf '%s' 'Elixir script'
        ;;
      erl)
        printf '%s' 'Erlang'
        ;;
      hrl)
        printf '%s' 'Erlang header'
        ;;
      hs)
        printf '%s' 'Haskell'
        ;;
      lhs)
        printf '%s' 'Literate Haskell'
        ;;
      ml)
        printf '%s' 'OCaml'
        ;;
      mli)
        printf '%s' 'OCaml interface'
        ;;

      js)
        printf '%s' 'JavaScript'
        ;;
      jsx)
        printf '%s' 'JSX'
        ;;
      mjs)
        printf '%s' 'JavaScript module'
        ;;
      cjs)
        printf '%s' 'CommonJS'
        ;;
      ts)
        printf '%s' 'TypeScript'
        ;;
      tsx)
        printf '%s' 'TSX'
        ;;
      mts)
        printf '%s' 'TypeScript module'
        ;;
      cts)
        printf '%s' 'TypeScript CommonJS'
        ;;
      vue)
        printf '%s' 'Vue'
        ;;
      svelte)
        printf '%s' 'Svelte'
        ;;
      astro)
        printf '%s' 'Astro'
        ;;

      sh)
        printf '%s' 'Shell'
        ;;
      bash)
        printf '%s' 'Bash'
        ;;
      zsh)
        printf '%s' 'Zsh'
        ;;
      fish)
        printf '%s' 'Fish'
        ;;
      ps1)
        printf '%s' 'PowerShell'
        ;;
      bat)
        printf '%s' 'Batch'
        ;;
      cmd)
        printf '%s' 'Windows command'
        ;;

      html|htm)
        printf '%s' 'HTML'
        ;;
      htmx)
        printf '%s' 'HTMX'
        ;;
      css)
        printf '%s' 'CSS'
        ;;
      scss)
        printf '%s' 'SCSS'
        ;;
      sass)
        printf '%s' 'Sass'
        ;;
      less)
        printf '%s' 'Less'
        ;;
      styl)
        printf '%s' 'Stylus'
        ;;
      hbs|handlebars)
        printf '%s' 'Handlebars'
        ;;
      mustache)
        printf '%s' 'Mustache'
        ;;
      ejs)
        printf '%s' 'EJS'
        ;;
      njk)
        printf '%s' 'Nunjucks'
        ;;
      twig)
        printf '%s' 'Twig'
        ;;
      liquid)
        printf '%s' 'Liquid'
        ;;

      sql)
        printf '%s' 'SQL'
        ;;
      graphql|gql)
        printf '%s' 'GraphQL'
        ;;
      proto)
        printf '%s' 'Protocol Buffers'
        ;;
      thrift)
        printf '%s' 'Thrift'
        ;;
      avsc)
        printf '%s' 'Avro schema'
        ;;
      wsdl)
        printf '%s' 'WSDL'
        ;;
      xsd)
        printf '%s' 'XML Schema'
        ;;
      xsl|xslt)
        printf '%s' 'XSLT'
        ;;
      prisma)
        printf '%s' 'Prisma schema'
        ;;
      feature)
        printf '%s' 'Gherkin'
        ;;
      robot)
        printf '%s' 'Robot Framework'
        ;;
      http|rest)
        printf '%s' 'HTTP request file'
        ;;

      tf)
        printf '%s' 'Terraform'
        ;;
      tfvars)
        printf '%s' 'Terraform variables'
        ;;
      hcl)
        printf '%s' 'HCL'
        ;;
      cue)
        printf '%s' 'CUE'
        ;;
      rego)
        printf '%s' 'Rego'
        ;;
      bicep)
        printf '%s' 'Bicep'
        ;;
      pp)
        printf '%s' 'Puppet'
        ;;

      json)
        printf '%s' 'JSON'
        ;;
      jsonc)
        printf '%s' 'JSON with comments'
        ;;
      json5)
        printf '%s' 'JSON5'
        ;;
      yaml|yml)
        printf '%s' 'YAML'
        ;;
      toml)
        printf '%s' 'TOML'
        ;;
      xml)
        printf '%s' 'XML'
        ;;
      ini)
        printf '%s' 'INI'
        ;;
      cfg|conf|config)
        printf '%s' 'Configuration'
        ;;
      properties)
        printf '%s' 'Properties'
        ;;
      env)
        printf '%s' 'Environment file'
        ;;
      lock)
        printf '%s' 'Lockfile'
        ;;

      md)
        printf '%s' 'Markdown'
        ;;
      mdx)
        printf '%s' 'MDX'
        ;;
      rst)
        printf '%s' 'reStructuredText'
        ;;
      adoc|asciidoc)
        printf '%s' 'AsciiDoc'
        ;;
      txt)
        printf '%s' 'Text'
        ;;
      tex)
        printf '%s' 'LaTeX'
        ;;
      bib)
        printf '%s' 'BibTeX'
        ;;
      mermaid|mmd)
        printf '%s' 'Mermaid'
        ;;
      puml|plantuml)
        printf '%s' 'PlantUML'
        ;;
      dot|gv)
        printf '%s' 'Graphviz'
        ;;

      csv)
        printf '%s' 'CSV'
        ;;
      tsv)
        printf '%s' 'TSV'
        ;;
      ndjson|jsonl)
        printf '%s' 'JSON Lines'
        ;;

      dart)
        printf '%s' 'Dart'
        ;;
      sol)
        printf '%s' 'Solidity'
        ;;
      asm|s)
        printf '%s' 'Assembly'
        ;;
      wat|wast)
        printf '%s' 'WebAssembly text'
        ;;
      v)
        printf '%s' 'Verilog'
        ;;
      sv)
        printf '%s' 'SystemVerilog'
        ;;
      svh)
        printf '%s' 'SystemVerilog header'
        ;;
      vhd|vhdl)
        printf '%s' 'VHDL'
        ;;
      templ)
        printf '%s' 'Go template'
        ;;
      promql)
        printf '%s' 'PromQL'
        ;;
      logql)
        printf '%s' 'LogQL'
        ;;

      *)
        # Unknown text extensions are still counted.
        printf '.%s' "$extension"
        ;;
    esac

    return
  fi

  # Classify extensionless text files by their shebang.
  first_line="$(LC_ALL=C head -n 1 "$file_path" 2>/dev/null || true)"

  case "$first_line" in
    '#!'*python*)
      printf '%s' 'Python script'
      ;;
    '#!'*ruby*)
      printf '%s' 'Ruby script'
      ;;
    '#!'*node*|'#!'*deno*)
      printf '%s' 'Node.js script'
      ;;
    '#!'*bash*)
      printf '%s' 'Bash script'
      ;;
    '#!'*zsh*)
      printf '%s' 'Zsh script'
      ;;
    '#!'*fish*)
      printf '%s' 'Fish script'
      ;;
    '#!'*sh*)
      printf '%s' 'Shell script'
      ;;
    '#!'*perl*)
      printf '%s' 'Perl script'
      ;;
    '#!'*php*)
      printf '%s' 'PHP script'
      ;;
    '#!'*)
      printf '%s' 'Shebang script'
      ;;
    *)
      printf '%s' '[extensionless text]'
      ;;
  esac
}

count_lines() {
  # awk counts a final unterminated line, unlike wc -l.
  LC_ALL=C awk 'END { print NR + 0 }' "$1" 2>/dev/null ||
    printf '0'
}

directory_count="$(
  find_project -type d -print |
    awk 'END { print (NR > 0 ? NR - 1 : 0) }'
)"

all_file_count="$(
  find_project -type f -print |
    awk 'END { print NR + 0 }'
)"

while IFS= read -r -d '' file_path; do
  if should_skip_file "$file_path"; then
    continue
  fi

  if is_text_file "$file_path"; then
    file_type="$(classify_file "$file_path")"
    line_count="$(count_lines "$file_path")"

    printf '%s\t%s\t%s\n' \
      "$file_type" \
      "$line_count" \
      "$file_path" >> "$STATS_FILE"

    case "$file_type" in
      .*|'[extensionless text]')
        printf '%s\t%s\t%s\n' \
          "$file_type" \
          "$line_count" \
          "$file_path" >> "$UNKNOWN_FILE"
        ;;
    esac
  else
    printf '%s\n' "$file_path" >> "$BINARY_FILE"
  fi
done < <(find_project -type f -print0)

text_file_count="$(
  awk 'END { print NR + 0 }' "$STATS_FILE"
)"

binary_file_count="$(
  awk 'END { print NR + 0 }' "$BINARY_FILE"
)"

unknown_text_file_count="$(
  awk 'END { print NR + 0 }' "$UNKNOWN_FILE"
)"

file_type_count="$(
  cut -f1 "$STATS_FILE" |
    LC_ALL=C sort -u |
    awk 'END { print NR + 0 }'
)"

total_text_lines="$(
  awk -F '\t' '
    {
      total += $2
    }
    END {
      print total + 0
    }
  ' "$STATS_FILE"
)"

printf '\nProject statistics\n'
printf '%s\n' '=================='
printf 'Root:                    %s\n' "$ROOT"
printf 'Directories:             %d\n' "$directory_count"
printf 'All project files:       %d\n' "$all_file_count"
printf 'Counted text files:      %d\n' "$text_file_count"
printf 'Text file types:         %d\n' "$file_type_count"
printf 'Unknown text types:      %d\n' "$unknown_text_file_count"
printf 'Binary files:            %d\n' "$binary_file_count"
printf 'Total counted lines:     %d\n\n' "$total_text_lines"

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
  LC_ALL=C sort -t $'\t' -k3,3nr -k2,2nr -k1,1 |
  awk -F '\t' '
    BEGIN {
      printf "%-32s %10s %15s\n", "FILE TYPE", "FILES", "LINES"
      printf "%-32s %10s %15s\n", "---------", "-----", "-----"
    }
    {
      printf "%-32s %10d %15d\n", $1, $2, $3
    }
  '

if [ -s "$UNKNOWN_FILE" ]; then
  printf '\nUnrecognized text types\n'
  printf '%s\n' '======================='
  printf '%s\n\n' \
    'These files were counted under their raw extension or as extensionless text.'

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
  ' "$UNKNOWN_FILE" |
    LC_ALL=C sort -t $'\t' -k3,3nr -k2,2nr -k1,1 |
    awk -F '\t' '
      BEGIN {
        printf "%-32s %10s %15s\n", "FILE TYPE", "FILES", "LINES"
        printf "%-32s %10s %15s\n", "---------", "-----", "-----"
      }
      {
        printf "%-32s %10d %15d\n", $1, $2, $3
      }
    '
fi

if [ "$SHOW_FILES" -eq 1 ]; then
  printf '\nCounted text files\n'
  printf '%s\n' '=================='

  LC_ALL=C sort -t $'\t' -k1,1 -k3,3 "$STATS_FILE" |
    awk -F '\t' '
      {
        printf "%-32s %10d  %s\n", $1, $2, $3
      }
    '
fi

if [ "$SHOW_BINARY" -eq 1 ] && [ -s "$BINARY_FILE" ]; then
  printf '\nBinary files\n'
  printf '%s\n' '============'
  LC_ALL=C sort "$BINARY_FILE"
fi

printf '\n'
