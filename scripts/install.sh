#!/usr/bin/env bash
# install.sh — install Dấu Fcitx5 addon (user-local or system).
# Usage: ./scripts/install.sh [--system] [--dry-run] [--help]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

MODE="user"   # user | system
DRY_RUN=0

usage() {
  cat <<'EOF'
Usage: ./scripts/install.sh [options]

Install the Dấu Fcitx5 addon after a successful build.

Options:
  --system     System-wide install (prefix /usr, requires sudo)
  --dry-run    Print commands without executing
  -h, --help   Show this help

Default (user-local, no sudo):
  prefix = $HOME/.local

Quick path from a clean clone (Linux):
  ./scripts/build.sh && ./scripts/install.sh

After install, enable "Dấu" in fcitx5-configtool and restart Fcitx5.
See docs/install-linux.md for details.
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

while [[ $# -gt 0 ]]; do
  case "$1" in
    --system)
      MODE="system"
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
echo "=== Dấu install (mode=${MODE}, OS=${OS}) ==="

if [[ "$OS" != "Linux" ]]; then
  echo "warning: install targets Linux Fcitx5 only (current OS=${OS})." >&2
  if [[ "$MODE" == "system" ]]; then
    PREFIX="/usr"
  else
    PREFIX="${HOME}/.local"
  fi
  ADDON_DIR="${ROOT}/platforms/linux"
  BUILD_DIR="${ADDON_DIR}/build"
  echo "[info] would configure with CMAKE_INSTALL_PREFIX=${PREFIX}"
  echo "[dry-run-paths]"
  echo "  lib:    ${PREFIX}/lib/fcitx5/libdau.so  (or distro multiarch libdir)"
  echo "  addon:  ${PREFIX}/share/fcitx5/addon/dau.conf"
  echo "  im:     ${PREFIX}/share/fcitx5/inputmethod/dau.conf"
  echo "  icons:  ${PREFIX}/share/icons/hicolor/"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    run_cmd cmake -S "${ADDON_DIR}" -B "${BUILD_DIR}" \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX="${PREFIX}"
    if [[ "$MODE" == "system" ]]; then
      echo "[dry-run] sudo cmake --install ${BUILD_DIR}"
    else
      echo "[dry-run] cmake --install ${BUILD_DIR}"
    fi
    echo "=== install dry-run done (non-Linux) ==="
    exit 0
  fi
  echo "error: cannot install Fcitx5 addon on ${OS}. Use --dry-run to preview." >&2
  exit 1
fi

if [[ "$MODE" == "system" ]]; then
  PREFIX="/usr"
else
  PREFIX="${HOME}/.local"
fi

ADDON_DIR="${ROOT}/platforms/linux"
BUILD_DIR="${ADDON_DIR}/build"

if ! command -v cmake >/dev/null 2>&1; then
  echo "error: cmake not found" >&2
  exit 1
fi

# Ensure release build with correct prefix, then install.
run_cmd cmake -S "${ADDON_DIR}" -B "${BUILD_DIR}" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="${PREFIX}"

if [[ ! -d "${BUILD_DIR}" ]] && [[ "$DRY_RUN" -eq 0 ]]; then
  echo "error: build directory missing; run ./scripts/build.sh first" >&2
  exit 1
fi

# Build if needed (install should not fail solely because user skipped build.sh).
if [[ "$DRY_RUN" -eq 1 ]]; then
  run_cmd cmake --build "${BUILD_DIR}"
else
  if [[ ! -f "${BUILD_DIR}/libdau.so" ]] && [[ ! -f "${BUILD_DIR}/libdau.dylib" ]]; then
    run_cmd cmake --build "${BUILD_DIR}"
  fi
fi

if [[ "$MODE" == "system" ]]; then
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "[dry-run] sudo cmake --install ${BUILD_DIR}"
  else
    printf '+ sudo cmake --install %s\n' "${BUILD_DIR}"
    sudo cmake --install "${BUILD_DIR}"
  fi
else
  run_cmd cmake --install "${BUILD_DIR}"
fi

echo
echo "Installed with prefix=${PREFIX}"
echo "Next:"
echo "  1. Open fcitx5-configtool → add input method → Dấu"
echo "  2. Restart Fcitx5: fcitx5 -r"
echo "  3. See docs/install-linux.md if Dấu does not appear"
echo "=== install done ==="
exit 0
