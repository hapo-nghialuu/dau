#!/usr/bin/env bash
# package-deb.sh — build Dấu .deb + tarball + SHA256SUMS for Linux/amd64.
# Shared by CI and Release workflows; runnable locally on Linux.
# Usage: ./scripts/package-deb.sh [--version X.Y.Z] [--out <dir>] [--help]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION=""
OUT_DIR="${ROOT}/dist"

usage() {
  cat <<'EOF'
Usage: ./scripts/package-deb.sh [options]

Build Dấu Debian package (.deb), source-layout tarball, and SHA256SUMS.
Requires Linux (dpkg-deb) and Fcitx5 development packages.

Options:
  --version X.Y.Z   Package version (default: parse from core/Cargo.toml)
  --out <dir>       Output directory (default: dist/)
  -h, --help        Show this help

Outputs (under --out):
  dau_<version>_amd64.deb
  dau-<version>-linux-x86_64.tar.gz
  SHA256SUMS
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      if [[ $# -lt 2 ]]; then
        echo "error: --version requires an argument" >&2
        exit 2
      fi
      VERSION="$2"
      shift 2
      ;;
    --out)
      if [[ $# -lt 2 ]]; then
        echo "error: --out requires an argument" >&2
        exit 2
      fi
      OUT_DIR="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

# --- Guard: Linux only ---
OS="$(uname -s 2>/dev/null || echo unknown)"
if [[ "$OS" != "Linux" ]]; then
  echo "error: package-deb.sh only runs on Linux (current OS=${OS})." >&2
  echo "       Use CI (ubuntu-latest) or a Linux host with dpkg-deb and Fcitx5 dev packages." >&2
  exit 1
fi

# --- Resolve version ---
if [[ -z "$VERSION" ]]; then
  VERSION="$(grep -E '^version\s*=' "${ROOT}/core/Cargo.toml" | head -1 | sed -E 's/^version\s*=\s*"([^"]+)".*/\1/')"
  if [[ -z "$VERSION" ]]; then
    echo "error: could not parse version from core/Cargo.toml" >&2
    exit 1
  fi
fi

# Absolute out dir
if [[ "$OUT_DIR" != /* ]]; then
  OUT_DIR="${ROOT}/${OUT_DIR}"
fi
mkdir -p "$OUT_DIR"

STAGING="$(mktemp -d "${TMPDIR:-/tmp}/dau-deb.XXXXXX")"
cleanup() {
  rm -rf "$STAGING"
}
trap cleanup EXIT

echo "=== Dấu package-deb (version=${VERSION}, out=${OUT_DIR}) ==="

# 1. Build core
echo "--- core (Rust) ---"
if ! command -v cargo >/dev/null 2>&1; then
  echo "error: cargo not found. Install Rust: https://rustup.rs" >&2
  exit 1
fi
cargo build --release --manifest-path "${ROOT}/core/Cargo.toml"

# 2. Build addon
echo "--- addon (Fcitx5 / CMake) ---"
if ! command -v cmake >/dev/null 2>&1; then
  echo "error: cmake not found" >&2
  exit 1
fi
cmake -S "${ROOT}/platforms/linux" -B "${ROOT}/platforms/linux/build" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX=/usr
cmake --build "${ROOT}/platforms/linux/build"

# 3. Staging install
echo "--- staging install ---"
DESTDIR="$STAGING" cmake --install "${ROOT}/platforms/linux/build"

# 4. DEBIAN/control
echo "--- DEBIAN/control ---"
mkdir -p "${STAGING}/DEBIAN"
cat > "${STAGING}/DEBIAN/control" <<EOF
Package: dau
Version: ${VERSION}
Architecture: amd64
Maintainer: Dấu Contributors <https://github.com/hapo-nghialuu/dau>
Depends: fcitx5
Section: utils
Priority: optional
Homepage: https://github.com/hapo-nghialuu/dau
Description: Vietnamese input method for Fcitx5 (Dau)
 Bo go tieng Viet cho Linux - nhanh, rieng tu, terminal & AI CLI first-class.
 Rust core + Fcitx5 addon. Telex/VNI, auto-restore, per-app strategy.
EOF

# 5. Build .deb
echo "--- dpkg-deb ---"
if ! command -v dpkg-deb >/dev/null 2>&1; then
  echo "error: dpkg-deb not found (install dpkg-dev)" >&2
  exit 1
fi
DEB_PATH="${OUT_DIR}/dau_${VERSION}_amd64.deb"
dpkg-deb --build --root-owner-group "$STAGING" "$DEB_PATH"

# 6. Tarball (usr tree only)
echo "--- tarball ---"
TARBALL_PATH="${OUT_DIR}/dau-${VERSION}-linux-x86_64.tar.gz"
tar czf "$TARBALL_PATH" -C "$STAGING" usr

# 7. SHA256SUMS
echo "--- SHA256SUMS ---"
(
  cd "$OUT_DIR"
  # shellcheck disable=SC2035
  sha256sum *.deb *.tar.gz > SHA256SUMS
)

# 8. Summary
echo
echo "=== package artifacts ==="
ls -la "$OUT_DIR"
echo
echo "=== dpkg-deb -I ==="
dpkg-deb -I "$DEB_PATH"
echo
echo "=== package-deb done ==="
echo "  deb:     $DEB_PATH"
echo "  tarball: $TARBALL_PATH"
echo "  sums:    ${OUT_DIR}/SHA256SUMS"
