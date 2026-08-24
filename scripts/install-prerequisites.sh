#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Pinned versions come from versions.env (single source of truth).
set +e
# shellcheck disable=SC1091
source "$ROOT_DIR/versions.env" 2>/dev/null
set -e
if [ -z "${GO_VERSION:-}" ] || [ -z "${KUBECTL_VERSION:-}" ] || [ -z "${K3D_VERSION:-}" ] || \
   [ -z "${TERRAFORM_VERSION:-}" ] || [ -z "${HELM_VERSION:-}" ]; then
  echo "ERROR: could not load pinned versions from $ROOT_DIR/versions.env" >&2
  exit 1
fi

OS="$(uname -s)"
PKG=""

have() {
  command -v "$1" >/dev/null 2>&1 && return 0
  case "$1" in
    go)          [ -x /usr/local/go/bin/go ] ;;
    cargo|rustc) [ -x "$HOME/.cargo/bin/$1" ] ;;
    dotnet)      [ -x "$HOME/.dotnet/dotnet" ] ;;
    *)           return 1 ;;
  esac
}

as_root() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    echo "ERROR: need root privileges to run: $*" >&2
    return 1
  fi
}

detect_pm() {
  if [ "$OS" = "Darwin" ]; then PKG=brew
  elif command -v apt-get >/dev/null 2>&1; then PKG=apt
  elif command -v dnf >/dev/null 2>&1; then PKG=dnf
  elif command -v pacman >/dev/null 2>&1; then PKG=pacman
  else
    echo "ERROR: unsupported platform ($OS): need Homebrew, apt, dnf, or pacman" >&2
    exit 1
  fi
}

pkg_install() {
  echo ">> installing via $PKG: $*"
  case "$PKG" in
    brew)   brew install "$@" ;;
    apt)    as_root apt-get update -qq && as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y "$@" ;;
    dnf)    as_root dnf install -y "$@" ;;
    pacman) as_root pacman -Sy --noconfirm --needed "$@" ;;
  esac
}

# Each candidate may span several brew args (e.g. "--cask temurin@25").
# shellcheck disable=SC2086
brew_install_first() {
  local candidate
  for candidate in "$@"; do
    # shellcheck disable=SC2086
    if brew install $candidate; then return 0; fi
  done
  echo "ERROR: no brew candidate succeeded: $*" >&2
  return 1
}

install_homebrew() {
  if have brew; then return 0; fi
  echo ">> installing Homebrew"
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  if [ -x /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [ -x /usr/local/bin/brew ]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
}

install_base_linux() {
  if [ -x "$(command -v curl)" ] && [ -x "$(command -v unzip)" ] && \
     [ -x "$(command -v zip)" ] && [ -x "$(command -v cc)" ]; then
    echo ">> base build tools present"
    return
  fi
  case "$PKG" in
    apt)    pkg_install build-essential curl ca-certificates unzip zip pkg-config libicu-dev ;;
    dnf)    pkg_install gcc-c++ make curl unzip zip libicu-devel ;;
    pacman) pkg_install base-devel curl unzip zip icu ;;
  esac
}

download_arch() {
  case "$(uname -m)" in
    x86_64)        echo amd64 ;;
    aarch64|arm64) echo arm64 ;;
    *) echo "ERROR: unsupported architecture: $(uname -m)" >&2; return 1 ;;
  esac
}

install_go() {
  if [ "$PKG" = "brew" ]; then
    pkg_install go
    return
  fi
  local arch tarball tmp
  arch="$(download_arch)"
  tarball="go${GO_VERSION}.linux-${arch}.tar.gz"
  echo ">> installing Go ${GO_VERSION} to /usr/local (${tarball})"
  tmp="$(fetch_to_tmp "https://go.dev/dl/${tarball}")"
  verify_sha "$tmp" "Go ${GO_VERSION}" "GO_SHA256_LINUX_${arch}"
  as_root rm -rf /usr/local/go
  as_root tar -C /usr/local -xzf "$tmp"
  rm -f "$tmp"
  export PATH="/usr/local/go/bin:$PATH"
}

install_java() {
  echo ">> installing JDK ${JAVA_VERSION}"
  case "$PKG" in
    brew)
      brew_install_first "--cask temurin@${JAVA_VERSION}" "--cask temurin" "openjdk@${JAVA_VERSION}" openjdk
      ;;
    apt)
      if ! pkg_install "openjdk-${JAVA_VERSION}-jdk"; then install_adoptium; fi
      ;;
    dnf)
      pkg_install "java-${JAVA_VERSION}-openjdk-devel" || pkg_install java-latest-openjdk-devel
      ;;
    pacman) pkg_install jdk-openjdk ;;
  esac
}

install_adoptium() {
  echo ">> adding the Adoptium (Temurin) apt repository"
  local codename
  # shellcheck disable=SC1091
  codename="$(. /etc/os-release && printf '%s' "${VERSION_CODENAME:-}")"
  if [ -z "$codename" ]; then
    echo "ERROR: cannot determine distro codename for the Adoptium repo" >&2
    return 1
  fi
  as_root install -d /etc/apt/keyrings
  curl -fsSL https://packages.adoptium.net/artifactory/api/gpg/key/public \
    | as_root gpg --dearmor --yes -o /etc/apt/keyrings/adoptium.gpg
  printf 'deb [signed-by=/etc/apt/keyrings/adoptium.gpg] https://packages.adoptium.net/artifactory/deb %s main\n' "$codename" \
    | as_root tee /etc/apt/sources.list.d/adoptium.list >/dev/null
  pkg_install "temurin-${JAVA_VERSION}-jdk"
}

install_clang_format() {
  case "$PKG" in
    brew|apt) pkg_install clang-format ;;
    dnf)      pkg_install clang-tools-extra ;;
    pacman)   pkg_install clang ;;
  esac
}

install_python() {
  case "$PKG" in
    brew)   pkg_install "python@${PYTHON_VERSION%.*}" ;;
    apt)    pkg_install python3 python3-venv python3-pip ;;
    dnf)    pkg_install python3 python3-pip ;;
    pacman) pkg_install python ;;
  esac
}

install_node() {
  local major prefixed
  major="${NODE_VERSION%%.*}"
  echo ">> installing Node.js ${NODE_VERSION}"
  case "$PKG" in
    brew)
      brew_install_first "node@${major}" node
      prefixed="$(brew --prefix)/opt/node@${major}/bin"
      if [ -d "$prefixed" ]; then export PATH="$prefixed:$PATH"; fi
      ;;
    apt)
      if curl -fsSL "https://deb.nodesource.com/setup_${major}.x" | as_root bash -; then
        pkg_install nodejs
      else
        pkg_install nodejs npm
      fi
      ;;
    dnf|pacman) pkg_install nodejs npm ;;
  esac
}

install_ruby() {
  case "$PKG" in
    brew)   pkg_install ruby ;;
    apt)    pkg_install ruby-full ruby-dev ;;
    dnf)    pkg_install ruby ruby-devel ;;
    pacman) pkg_install ruby ;;
  esac
}

# Arch/Fedora/Debian split bundler out of the ruby package; prefer the distro
# package because a plain user-level `gem install` drops `bundle` into an
# off-PATH bin dir while still exiting 0.
install_bundler() {
  echo ">> installing bundler"
  case "$PKG" in
    apt)    pkg_install bundler || install_bundler_gem ;;
    dnf)    pkg_install rubygem-bundler || install_bundler_gem ;;
    # ruby-erb is a split package on Arch; rubocop/bundler need it to boot
    pacman) pkg_install ruby-bundler ruby-erb || install_bundler_gem ;;
    *)      install_bundler_gem ;;
  esac
  if ! have bundle; then
    echo "ERROR: bundler installed but 'bundle' is not on PATH" >&2
    exit 1
  fi
}

install_bundler_gem() {
  gem install bundler --no-document || as_root gem install bundler --no-document
}

verify_installer_sha256() {
  local file="$1"
  local expected="$2"
  local actual
  if command -v sha256sum >/dev/null 2>&1; then
    actual="$(sha256sum "$file" | awk '{print $1}')"
  else
    actual="$(shasum -a 256 "$file" | awk '{print $1}')"
  fi
  if [ "$actual" != "$expected" ]; then
    echo "ERROR: installer checksum mismatch (expected $expected, got $actual)" >&2
    exit 1
  fi
}

install_rust() {
  echo ">> installing Rust ${RUST_VERSION} via rustup ${RUSTUP_VERSION}"
  local tmp
  tmp="$(mktemp)"
  curl -fsSL "https://raw.githubusercontent.com/rust-lang/rustup/${RUSTUP_VERSION}/rustup-init.sh" -o "$tmp"
  verify_installer_sha256 "$tmp" "${RUSTUP_INIT_SHA256:-}"
  sh "$tmp" -y --profile minimal --default-toolchain "${RUST_VERSION}" -c rustfmt -c clippy
  rm -f "$tmp"
  export PATH="$HOME/.cargo/bin:$PATH"
}

install_dotnet() {
  echo ">> installing .NET SDK ${DOTNET_SDK_VERSION} via dotnet-install.sh"
  local tmp
  tmp="$(mktemp)"
  curl -fsSL https://dot.net/v1/dotnet-install.sh -o "$tmp"
  bash "$tmp" --version "${DOTNET_SDK_VERSION}" --install-dir "$HOME/.dotnet"
  rm -f "$tmp"
  export PATH="$HOME/.dotnet:$PATH"
}

# uv provisions the pinned CPython for the Python venv even when the system
# python3 is newer than the pinned wheel set supports (user-local, no sudo).
install_uv() {
  # UV_VERSION comes from the sourced versions.env; shellcheck cannot see it.
  # shellcheck disable=SC2153
  echo ">> installing uv ${UV_VERSION} (~/.local/bin)"
  local tmp
  tmp="$(mktemp)"
  curl -fsSL "https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/uv-installer.sh" -o "$tmp"
  verify_installer_sha256 "$tmp" "${UV_INSTALLER_SHA256:-}"
  sh "$tmp"
  rm -f "$tmp"
  export PATH="$HOME/.local/bin:$PATH"
}

install_shellcheck() {
  case "$PKG" in
    dnf) pkg_install ShellCheck ;;
    *)   pkg_install shellcheck ;;
  esac
}

install_librdkafka() {
  case "$PKG" in
    brew)   pkg_install librdkafka ;;
    apt)    pkg_install librdkafka-dev ;;
    dnf)    pkg_install librdkafka-devel ;;
    pacman) pkg_install librdkafka ;;
  esac
}

install_markdownlint() {
  echo ">> installing markdownlint-cli2 (npm global)"
  npm install -g markdownlint-cli2 || as_root npm install -g markdownlint-cli2
}

install_docker() {
  case "$PKG" in
    brew)   pkg_install colima docker ;;
    apt)    pkg_install docker.io ;;
    dnf)    pkg_install moby-engine ;;
    pacman) pkg_install docker ;;
  esac
}

# k3d drives /var/run/docker.sock as the invoking user, so the daemon must be
# up and the user in the docker group; group changes only apply after re-login.
ensure_docker_runtime() {
  if command -v systemctl >/dev/null 2>&1 && ! docker info >/dev/null 2>&1; then
    echo ">> enabling the docker daemon (systemctl enable --now docker)"
    as_root systemctl enable --now docker || echo "WARN: could not enable docker.service; start it manually" >&2
  fi
  if [ "$(id -u)" -ne 0 ] && ! id -nG "$(id -un)" | grep -qw docker; then
    echo ">> adding $(id -un) to the docker group (effective after re-login)"
    if as_root usermod -aG docker "$(id -un)"; then
      echo "NOTE: log out and back in, or run: sg docker -c './rghw.sh --fresh'"
    else
      echo "WARN: could not add $(id -un) to the docker group; docker.sock will be inaccessible until fixed manually" >&2
    fi
  fi
}

fetch_to_tmp() {
  local tmp
  tmp="$(mktemp)"
  curl -fsSL "$1" -o "$tmp"
  printf '%s' "$tmp"
}

# Verify a downloaded artifact against its versions.env pin
# (<TOOL>_SHA256_LINUX_<arch>). A missing pin warns instead of failing so a
# version bump never bricks the installer, but every pin that exists is
# enforced: a mismatch refuses the root install outright.
verify_sha() {
  local file="$1" tool="$2" var actual
  # Pin names are uppercase; download_arch yields lowercase.
  var="$(printf '%s' "$3" | tr '[:lower:]' '[:upper:]')"
  if [ -z "${!var+x}" ]; then
    echo "WARN: ${var} not pinned in versions.env; skipping checksum verification for $tool" >&2
    return 0
  fi
  if [ -z "${!var}" ]; then
    echo "ERROR: ${var} is set but empty in versions.env; refusing to install $tool" >&2
    exit 1
  fi
  actual="$(sha256sum "$file" | awk '{print $1}')"
  if [ "$actual" != "${!var}" ]; then
    echo "ERROR: $tool checksum mismatch (${var} expected, got ${actual}); refusing to install" >&2
    exit 1
  fi
  echo ">> verified $tool checksum"
}

install_kubectl() {
  if [ "$PKG" = "brew" ]; then pkg_install kubectl; return; fi
  local arch tmp
  arch="$(download_arch)"
  echo ">> installing kubectl v${KUBECTL_VERSION} to /usr/local/bin"
  tmp="$(fetch_to_tmp "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/${arch}/kubectl")"
  verify_sha "$tmp" "kubectl v${KUBECTL_VERSION}" "KUBECTL_SHA256_LINUX_${arch}"
  as_root install -m 0755 "$tmp" /usr/local/bin/kubectl
  rm -f "$tmp"
}

install_k3d() {
  if [ "$PKG" = "brew" ]; then pkg_install k3d; return; fi
  local arch tmp
  arch="$(download_arch)"
  echo ">> installing k3d v${K3D_VERSION} to /usr/local/bin"
  tmp="$(fetch_to_tmp "https://github.com/k3d-io/k3d/releases/download/v${K3D_VERSION}/k3d-linux-${arch}")"
  verify_sha "$tmp" "k3d v${K3D_VERSION}" "K3D_SHA256_LINUX_${arch}"
  as_root install -m 0755 "$tmp" /usr/local/bin/k3d
  rm -f "$tmp"
}

install_terraform() {
  if [ "$PKG" = "brew" ]; then brew_install_first "hashicorp/tap/terraform" terraform; return; fi
  local arch tmp dir
  arch="$(download_arch)"
  echo ">> installing terraform ${TERRAFORM_VERSION} to /usr/local/bin"
  tmp="$(fetch_to_tmp "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_${arch}.zip")"
  verify_sha "$tmp" "terraform ${TERRAFORM_VERSION}" "TERRAFORM_SHA256_LINUX_${arch}"
  dir="$(mktemp -d)"
  unzip -oq "$tmp" -d "$dir"
  as_root install -m 0755 "$dir/terraform" /usr/local/bin/terraform
  rm -rf "$dir" "$tmp"
}

install_helm() {
  if [ "$PKG" = "brew" ]; then pkg_install helm; return; fi
  local arch tmp dir
  arch="$(download_arch)"
  echo ">> installing helm v${HELM_VERSION} to /usr/local/bin"
  tmp="$(fetch_to_tmp "https://get.helm.sh/helm-v${HELM_VERSION}-linux-${arch}.tar.gz")"
  verify_sha "$tmp" "helm v${HELM_VERSION}" "HELM_SHA256_LINUX_${arch}"
  dir="$(mktemp -d)"
  tar -xzf "$tmp" -C "$dir"
  as_root install -m 0755 "$dir/linux-${arch}/helm" /usr/local/bin/helm
  rm -rf "$dir" "$tmp"
}

have_librdkafka() {
  [ -e /opt/homebrew/include/librdkafka/rdkafka.h ] ||
    [ -e /usr/local/include/librdkafka/rdkafka.h ] ||
    [ -e /usr/include/librdkafka/rdkafka.h ]
}

# Go tarball and dotnet-install do not persist PATH; write one managed block so
# fresh shells find every toolchain installed here.
persist_shell_path() {
  local marker="rghw toolchain paths"
  local block rc path_line
  # The block must stay unexpanded in the rc file.
  # shellcheck disable=SC2016
  path_line='export PATH="/usr/local/go/bin:$HOME/.dotnet:$HOME/.cargo/bin:$HOME/.local/bin:$PATH"'
  block="$(printf '%s\n' \
    "# >>> ${marker} >>>" \
    "$path_line" \
    "# <<< ${marker} <<<")"
  # zsh is macOS's default login shell; cover it wherever an rc file exists.
  for rc in "$HOME/.bashrc" "$HOME/.profile" "$HOME/.zshrc"; do
    [ -f "$rc" ] || continue
    if grep -qs "$marker" "$rc"; then continue; fi
    printf '\n%s\n' "$block" >> "$rc"
    echo ">> added toolchain PATH block to $rc"
  done
}

main() {
  detect_pm
  echo "Rube Goldberg Hello World - prerequisite installer ($OS / $PKG)"
  echo ""

  if [ "$OS" = "Darwin" ]; then install_homebrew; fi
  if [ "$OS" = "Linux" ]; then install_base_linux; fi

  if have go; then echo ">> go present"; else install_go; fi
  if have java && have javac; then echo ">> JDK present"; else install_java; fi
  if have mvn; then echo ">> maven present"; else pkg_install maven; fi
  if have cmake; then echo ">> cmake present"; else pkg_install cmake; fi
  if have clang-format; then echo ">> clang-format present"; else install_clang_format; fi
  if have python3; then echo ">> python3 present"; else install_python; fi
  if have node && have npm; then echo ">> Node.js present"; else install_node; fi
  if have ruby; then echo ">> ruby present"; else install_ruby; fi
  if have bundle; then echo ">> bundler present"; else install_bundler; fi
  if have cargo && have rustc; then echo ">> Rust present"; else install_rust; fi
  if have dotnet; then echo ">> .NET SDK present"; else install_dotnet; fi
  if have uv; then echo ">> uv present"; else install_uv; fi

  if have shellcheck; then echo ">> shellcheck present"; else install_shellcheck; fi
  if have markdownlint-cli2; then echo ">> markdownlint-cli2 present"; else install_markdownlint; fi
  if have_librdkafka; then
    echo ">> librdkafka headers present"
  elif ! install_librdkafka; then
    echo "WARN: librdkafka headers not installed automatically; C++ service builds will skip"
  fi

  echo ""
  echo "-- infrastructure required by ./rghw.sh --"
  if have docker; then echo ">> docker present"; else install_docker; fi
  if have kubectl; then echo ">> kubectl present"; else install_kubectl; fi
  if have k3d; then echo ">> k3d present"; else install_k3d; fi
  if have terraform; then echo ">> terraform present"; else install_terraform; fi
  if have helm; then echo ">> helm present"; else install_helm; fi
  if [ "$OS" = "Linux" ]; then ensure_docker_runtime; fi

  persist_shell_path

  echo ""
  echo ">> verifying toolchains + preparing language dependencies via scripts/prerequisites.sh"
  exec bash "$ROOT_DIR/scripts/prerequisites.sh"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
