#!/usr/bin/env bash
# uninstall.sh — remove Dấu Fcitx5 addon, conf, and icons.
# Usage: ./scripts/uninstall.sh [--system] [--dry-run] [--help]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

MODE="user"   # user | system
DRY_RUN=0

usage() {
  cat <<'EOF'
Usage: ./scripts/uninstall.sh [options]

Remove Dấu Fcitx5 addon files (shared library, conf, icons).

Options:
  --system     Remove system-wide install (prefix /usr, requires sudo)
  --dry-run    Print paths / commands without deleting
  -h, --help   Show this help

Default removes user-local install under $HOME/.local.
EOF
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

if [[ "$MODE" == "system" ]]; then
  PREFIX="/usr"
  SUDO="sudo"
else
  PREFIX="${HOME}/.local"
  SUDO=""
fi

echo "=== Dấu uninstall (mode=${MODE}, prefix=${PREFIX}, OS=${OS}) ==="

# Candidate paths (distro multiarch + plain lib).
CANDIDATES=(
  "${PREFIX}/lib/fcitx5/libdau.so"
  "${PREFIX}/lib64/fcitx5/libdau.so"
  "${PREFIX}/lib/x86_64-linux-gnu/fcitx5/libdau.so"
  "${PREFIX}/lib/aarch64-linux-gnu/fcitx5/libdau.so"
  "${PREFIX}/share/fcitx5/addon/dau.conf"
  "${PREFIX}/share/fcitx5/inputmethod/dau.conf"
)

# Icon sizes used by packaging.
ICON_SIZES="16x16 22x22 24x24 32x32 48x48 64x64 128x128 256x256"
for size in $ICON_SIZES; do
  CANDIDATES+=("${PREFIX}/share/icons/hicolor/${size}/apps/dau.png")
done
CANDIDATES+=("${PREFIX}/share/icons/hicolor/scalable/apps/dau.svg")

rm_path() {
  local path="$1"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    if [[ -e "$path" ]] || [[ "$OS" != "Linux" ]]; then
      echo "[dry-run] ${SUDO:+$SUDO }rm -f ${path}"
    else
      echo "[skip]    not found: ${path}"
    fi
    return
  fi
  if [[ -e "$path" ]]; then
    if [[ -n "$SUDO" ]]; then
      printf '+ sudo rm -f %s\n' "$path"
      sudo rm -f "$path"
    else
      printf '+ rm -f %s\n' "$path"
      rm -f "$path"
    fi
  else
    echo "[skip]    not found: ${path}"
  fi
}

for p in "${CANDIDATES[@]}"; do
  rm_path "$p"
done

# Optional: refresh icon cache if tool exists (best-effort).
if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "[dry-run] gtk-update-icon-cache -f -t ${PREFIX}/share/icons/hicolor  # if available"
else
  if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    if [[ -d "${PREFIX}/share/icons/hicolor" ]]; then
      if [[ -n "$SUDO" ]]; then
        sudo gtk-update-icon-cache -f -t "${PREFIX}/share/icons/hicolor" 2>/dev/null || true
      else
        gtk-update-icon-cache -f -t "${PREFIX}/share/icons/hicolor" 2>/dev/null || true
      fi
    fi
  fi
fi

echo "=== uninstall done ==="
echo "Restart Fcitx5 if it is running: fcitx5 -r"
exit 0
