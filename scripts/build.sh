#!/usr/bin/env bash
# build.sh — build dau-core (Rust) then Fcitx5 addon (C++).
# Usage: ./scripts/build.sh [--debug] [--dry-run] [--help]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BUILD_TYPE="Release"
CARGO_FLAGS=(--release)
DRY_RUN=0

usage() {
  cat <<'EOF'
Usage: ./scripts/build.sh [options]

Build Dấu core (Rust) and Linux Fcitx5 addon (CMake).

Options:
  --debug      Build debug artifacts (cargo without --release; CMAKE_BUILD_TYPE=Debug)
  --dry-run    Print commands without executing
  -h, --help   Show this help

Notes:
  - On macOS / systems without fcitx5, only the Rust core is built.
    Addon build requires Linux + fcitx5 development packages.
  - Exit 0 after core build with a warning when addon cannot be built.
EOF
}

run_cmd() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf '[dry-run] %s\n' "$*"
  else
    printf '+ %s\n' "$*"
    "$@"
  fi
}

have_fcitx5_dev() {
  # Portable checks: pkg-config module or known include/lib layout.
  if command -v pkg-config >/dev/null 2>&1; then
    if pkg-config --exists Fcitx5Core 2>/dev/null || pkg-config --exists fcitx5 2>/dev/null; then
      return 0
    fi
  fi
  if [[ -d /usr/include/Fcitx5/Core ]] || [[ -d /usr/local/include/Fcitx5/Core ]]; then
    return 0
  fi
  return 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --debug)
      BUILD_TYPE="Debug"
      CARGO_FLAGS=()
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

OS="$(uname -s 2>/dev/null || echo unknown)"
echo "=== Dấu build (OS=${OS}, type=${BUILD_TYPE}) ==="

# --- Core (always) ---
if ! command -v cargo >/dev/null 2>&1; then
  echo "error: cargo not found. Install Rust: https://rustup.rs" >&2
  exit 1
fi

echo "--- core (Rust) ---"
# Portable empty-array handling (bash 3.2 on macOS + set -u).
if [[ ${#CARGO_FLAGS[@]} -gt 0 ]]; then
  run_cmd cargo build "${CARGO_FLAGS[@]}" --manifest-path "${ROOT}/core/Cargo.toml"
else
  run_cmd cargo build --manifest-path "${ROOT}/core/Cargo.toml"
fi

# --- Addon (Linux + fcitx5) ---
echo "--- addon (Fcitx5) ---"
if [[ "$OS" != "Linux" ]]; then
  echo "warning: Fcitx5 addon requires Linux (current OS=${OS}). Core build only." >&2
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "[dry-run] would skip: cmake -B platforms/linux/build && cmake --build platforms/linux/build"
  fi
  echo "=== build done (core only) ==="
  exit 0
fi

if ! command -v cmake >/dev/null 2>&1; then
  echo "warning: cmake not found; cannot build addon. Core is ready." >&2
  exit 0
fi

if ! have_fcitx5_dev; then
  echo "warning: fcitx5 development packages not detected; cannot build addon. Core is ready." >&2
  echo "         Install e.g. fcitx5, libfcitx5core-dev, libfcitx5utils-dev, cmake, g++" >&2
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "[dry-run] would skip: cmake configure + build for platforms/linux"
  fi
  exit 0
fi

ADDON_DIR="${ROOT}/platforms/linux"
BUILD_DIR="${ADDON_DIR}/build"

run_cmd cmake -S "${ADDON_DIR}" -B "${BUILD_DIR}" -DCMAKE_BUILD_TYPE="${BUILD_TYPE}"
run_cmd cmake --build "${BUILD_DIR}"

echo "=== build done ==="
exit 0
