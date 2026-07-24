#!/usr/bin/env bash
# scripts/build/macos.sh — build dau-core (Rust staticlib) then Dau.app via xcodebuild.
# WP-01: --debug / --adhoc are the primary paths. --sign / --notarize are scaffolded for P4.
#
# Usage:
#   ./scripts/build/macos.sh --debug
#   ./scripts/build/macos.sh --adhoc
#   ./scripts/build/macos.sh --adhoc --arch universal
#   ./scripts/build/macos.sh --sign --arch universal   # needs APPLE_SIGNING_IDENTITY
#   ./scripts/build/macos.sh --notarize --arch universal
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MACOS_DIR="$ROOT/platforms/macos"
CORE_DIR="$ROOT/core"
LIB_DIR="$MACOS_DIR/build/lib"
DERIVED_DATA="$MACOS_DIR/build/DerivedData"
PRODUCTS_DIR="$MACOS_DIR/build"

if [[ -f "$HOME/.cargo/env" ]]; then
  # shellcheck source=/dev/null
  source "$HOME/.cargo/env"
fi

MODE=""
ARCH="host"
VERSION="0.1.0"
DRY_RUN=0

usage() {
  cat <<'EOF'
Usage: ./scripts/build/macos.sh [mode] [options]

Modes (exactly one required):
  --debug       Build cargo (debug) + xcodebuild Debug
  --adhoc       Build cargo (release) + xcodebuild Release + ad-hoc codesign
  --sign        Release build + Developer ID codesign (hardened runtime)
  --notarize    Same as --sign, then notarytool submit + staple

Options:
  --arch ARCH   host (default) | arm64 | x86_64 | universal
  --version V   Marketing/version string (default: 0.1.0)
  --dry-run     Print planned commands only
  -h, --help    Show this help

Outputs:
  platforms/macos/build/lib/libdau_core.a
  platforms/macos/build/Debug/Dau.app   (or Release/)

Env for --sign / --notarize:
  APPLE_SIGNING_IDENTITY   e.g. "Developer ID Application: Name (TEAM)"
  APPLE_TEAM_ID            optional but recommended
  NOTARY_PROFILE           keychain profile for notarytool (preferred)
  or APPLE_ID + APPLE_APP_PASSWORD + APPLE_TEAM_ID

Notes:
  - Does not modify TCC / Accessibility databases.
  - Bundle ID placeholder: io.github.hapo-nghialuu.dau (see platforms/macos/README.md)
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

host_triple() {
  local m
  m="$(uname -m)"
  case "$m" in
    arm64|aarch64) echo "aarch64-apple-darwin" ;;
    x86_64) echo "x86_64-apple-darwin" ;;
    *)
      echo "Unsupported host arch: $m" >&2
      exit 1
      ;;
  esac
}

triple_for_arch() {
  case "$1" in
    host) echo "$(host_triple)" ;;
    arm64) echo "aarch64-apple-darwin" ;;
    x86_64) echo "x86_64-apple-darwin" ;;
    universal) echo "universal" ;;
    *)
      echo "Unknown --arch value: $1 (expected host|arm64|x86_64|universal)" >&2
      exit 2
      ;;
  esac
}

cargo_profile_flags() {
  if [[ "$MODE" == "debug" ]]; then
    echo ""
  else
    echo "--release"
  fi
}

cargo_out_dir() {
  local triple="$1"
  local profile
  if [[ "$MODE" == "debug" ]]; then
    profile="debug"
  else
    profile="release"
  fi
  if [[ "$triple" == "host" ]]; then
    echo "$CORE_DIR/target/$profile"
  else
    echo "$CORE_DIR/target/$triple/$profile"
  fi
}

build_one_core() {
  local triple="$1"
  local flags
  flags="$(cargo_profile_flags)"
  # shellcheck disable=SC2086
  if [[ "$triple" == "host" ]]; then
    run_cmd cargo build --manifest-path "$CORE_DIR/Cargo.toml" $flags
  else
    run_cmd cargo build --manifest-path "$CORE_DIR/Cargo.toml" $flags --target "$triple"
  fi
}

stage_lib() {
  local src="$1"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf '[dry-run] mkdir -p %s && cp %s %s/libdau_core.a\n' "$LIB_DIR" "$src" "$LIB_DIR"
    return 0
  fi
  mkdir -p "$LIB_DIR"
  if [[ ! -f "$src" ]]; then
    echo "error: expected static library missing: $src" >&2
    exit 1
  fi
  cp -f "$src" "$LIB_DIR/libdau_core.a"
  echo "Staged: $LIB_DIR/libdau_core.a"
  if command -v lipo >/dev/null 2>&1; then
    lipo -info "$LIB_DIR/libdau_core.a" || true
  fi
}

build_core() {
  local mapped
  mapped="$(triple_for_arch "$ARCH")"
  echo "=== dau-core (mode=$MODE arch=$ARCH → $mapped) ==="

  if [[ "$mapped" == "universal" ]]; then
    local profile
    if [[ "$MODE" == "debug" ]]; then
      profile="debug"
    else
      profile="release"
    fi
    build_one_core "aarch64-apple-darwin"
    build_one_core "x86_64-apple-darwin"
    local a="$CORE_DIR/target/aarch64-apple-darwin/$profile/libdau_core.a"
    local b="$CORE_DIR/target/x86_64-apple-darwin/$profile/libdau_core.a"
    if [[ "$DRY_RUN" -eq 1 ]]; then
      printf '[dry-run] lipo -create %s %s -output %s/libdau_core.a\n' "$a" "$b" "$LIB_DIR"
    else
      mkdir -p "$LIB_DIR"
      lipo -create "$a" "$b" -output "$LIB_DIR/libdau_core.a"
      echo "Staged universal: $LIB_DIR/libdau_core.a"
      lipo -info "$LIB_DIR/libdau_core.a"
    fi
  elif [[ "$mapped" == "$(host_triple)" && "$ARCH" == "host" ]]; then
    # Prefer default host layout (no --target) for simplest local builds.
    build_one_core "host"
    stage_lib "$(cargo_out_dir host)/libdau_core.a"
  else
    build_one_core "$mapped"
    stage_lib "$(cargo_out_dir "$mapped")/libdau_core.a"
  fi
}

xcode_configuration() {
  if [[ "$MODE" == "debug" ]]; then
    echo "Debug"
  else
    echo "Release"
  fi
}

build_xcode() {
  local config
  config="$(xcode_configuration)"
  echo "=== xcodebuild (configuration=$config version=$VERSION) ==="

  if [[ ! -d "$MACOS_DIR/Dau.xcodeproj" ]]; then
    echo "error: missing $MACOS_DIR/Dau.xcodeproj" >&2
    exit 1
  fi
  if [[ ! -f "$LIB_DIR/libdau_core.a" && "$DRY_RUN" -eq 0 ]]; then
    echo "error: $LIB_DIR/libdau_core.a missing; core stage failed" >&2
    exit 1
  fi

  local -a xb=(
    xcodebuild
    -project "$MACOS_DIR/Dau.xcodeproj"
    -scheme Dau
    -configuration "$config"
    -sdk macosx
    -derivedDataPath "$DERIVED_DATA"
    MARKETING_VERSION="$VERSION"
    CURRENT_PROJECT_VERSION="$VERSION"
    CODE_SIGN_IDENTITY="-"
    CODE_SIGN_STYLE=Manual
    DEVELOPMENT_TEAM=
  )

  # Match Xcode ARCHS to the staged staticlib. Host must not build the other
  # slice: Release defaults to ONLY_ACTIVE_ARCH=NO and will fail linking
  # arm64-only libdau_core.a against an x86_64 object (and vice versa).
  if [[ "$ARCH" == "host" ]]; then
    case "$(uname -m)" in
      arm64|aarch64) xb+=(ARCHS=arm64 ONLY_ACTIVE_ARCH=YES) ;;
      x86_64) xb+=(ARCHS=x86_64 ONLY_ACTIVE_ARCH=YES) ;;
      *)
        echo "error: unsupported host arch for xcodebuild: $(uname -m)" >&2
        exit 1
        ;;
    esac
  elif [[ "$ARCH" == "arm64" ]]; then
    xb+=(ARCHS=arm64 ONLY_ACTIVE_ARCH=NO)
  elif [[ "$ARCH" == "x86_64" ]]; then
    xb+=(ARCHS=x86_64 ONLY_ACTIVE_ARCH=NO)
  elif [[ "$ARCH" == "universal" ]]; then
    xb+=(ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO)
  fi

  xb+=(build)

  run_cmd "${xb[@]}"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    return 0
  fi

  local built_app="$DERIVED_DATA/Build/Products/$config/Dau.app"
  local out_dir="$PRODUCTS_DIR/$config"
  mkdir -p "$out_dir"
  rm -rf "$out_dir/Dau.app"
  cp -R "$built_app" "$out_dir/Dau.app"
  echo "App: $out_dir/Dau.app"
}

sign_adhoc() {
  local app="$PRODUCTS_DIR/Release/Dau.app"
  local ents="$MACOS_DIR/Resources/Dau.entitlements.dev"
  if [[ "$MODE" != "debug" ]]; then
    # Ad-hoc / local release uses production entitlements (no get-task-allow).
    ents="$MACOS_DIR/Resources/Dau.entitlements.production"
  fi
  if [[ ! -d "$app" && "$DRY_RUN" -eq 0 ]]; then
    echo "error: app missing for codesign: $app" >&2
    exit 1
  fi
  run_cmd codesign --force --deep --sign - --entitlements "$ents" "$app"
  run_cmd codesign --verify --deep --strict --verbose=2 "$app" || true
  echo "Ad-hoc signed: $app"
}

sign_developer_id() {
  local app="$PRODUCTS_DIR/Release/Dau.app"
  local ents="$MACOS_DIR/Resources/Dau.entitlements.production"
  if [[ -z "${APPLE_SIGNING_IDENTITY:-}" ]]; then
    echo "error: APPLE_SIGNING_IDENTITY is required for --sign/--notarize" >&2
    echo "hint: security find-identity -v -p codesigning" >&2
    exit 1
  fi
  run_cmd codesign --force --deep --sign "$APPLE_SIGNING_IDENTITY" \
    --entitlements "$ents" \
    --options runtime \
    --timestamp \
    "$app"
  run_cmd codesign --verify --deep --strict --verbose=2 "$app"
  echo "Developer ID signed: $app"
}

notarize_app() {
  local app="$PRODUCTS_DIR/Release/Dau.app"
  local zip="$PRODUCTS_DIR/Release/Dau-notarize.zip"
  run_cmd ditto -c -k --keepParent "$app" "$zip"

  if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    run_cmd xcrun notarytool submit "$zip" --keychain-profile "$NOTARY_PROFILE" --wait
  elif [[ -n "${APPLE_ID:-}" && -n "${APPLE_APP_PASSWORD:-}" && -n "${APPLE_TEAM_ID:-}" ]]; then
    run_cmd xcrun notarytool submit "$zip" \
      --apple-id "$APPLE_ID" \
      --password "$APPLE_APP_PASSWORD" \
      --team-id "$APPLE_TEAM_ID" \
      --wait
  else
    echo "error: set NOTARY_PROFILE or APPLE_ID + APPLE_APP_PASSWORD + APPLE_TEAM_ID" >&2
    exit 1
  fi

  run_cmd xcrun stapler staple "$app"
  run_cmd spctl -a -vvv -t install "$app" || true
  if [[ "$DRY_RUN" -eq 0 ]]; then
    rm -f "$zip"
  fi
  echo "Notarized: $app"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --debug|--adhoc|--sign|--notarize)
      if [[ -n "$MODE" ]]; then
        echo "error: only one mode allowed (already set to --$MODE)" >&2
        exit 2
      fi
      MODE="${1#--}"
      shift
      ;;
    --arch)
      ARCH="${2:-}"
      if [[ -z "$ARCH" ]]; then
        echo "error: --arch needs a value" >&2
        exit 2
      fi
      shift 2
      ;;
    --version)
      VERSION="${2:-}"
      if [[ -z "$VERSION" ]]; then
        echo "error: --version needs a value" >&2
        exit 2
      fi
      shift 2
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

if [[ -z "$MODE" ]]; then
  echo "error: choose --debug, --adhoc, --sign, or --notarize" >&2
  usage >&2
  exit 2
fi

if ! command -v cargo >/dev/null 2>&1; then
  echo "error: cargo not found in PATH" >&2
  exit 1
fi
if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "error: xcodebuild not found (install Xcode)" >&2
  exit 1
fi

echo "=== Dấu macOS build (mode=$MODE arch=$ARCH version=$VERSION) ==="
echo "ROOT=$ROOT"

build_core
build_xcode

case "$MODE" in
  debug)
    echo "Debug build complete (no extra codesign step beyond Xcode Manual/-)."
    echo "App: $PRODUCTS_DIR/Debug/Dau.app"
    ;;
  adhoc)
    sign_adhoc
    ;;
  sign)
    sign_developer_id
    ;;
  notarize)
    sign_developer_id
    notarize_app
    ;;
esac

echo "=== done ==="
