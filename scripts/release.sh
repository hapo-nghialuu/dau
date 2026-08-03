#!/usr/bin/env bash
# scripts/release.sh — macOS release pipeline for Dấu.
#
# Builds Dau.app (ad-hoc signed), packages Dau-<VERSION>.zip, computes SHA256,
# and (unless --dry-run) runs the publish phase: gh release + local cask SHA.
#
# Usage:
#   ./scripts/release.sh 0.2.0
#   ./scripts/release.sh 0.2.0 --dry-run
#   ./scripts/release.sh 0.2.0 --skip-build --dry-run
#   ./scripts/release.sh 0.2.0 --arch arm64
#   ./scripts/release.sh -h | --help
#
# Notes:
#   - Universal (arm64 + x86_64) is the default architecture; build fails
#     early when rustup lacks the target or lipo is unavailable, and the
#     packaged app executable is verified with `lipo -info` before zipping.
#   - Does not run `git push` or an explicit `git tag`; `gh release create`
#     creates the release tag after the source commit is reviewed locally.
#   - --dry-run shows planned paths without compiling or publishing.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BUILD_SCRIPT="$ROOT/scripts/build/macos.sh"
APP_DIR="$ROOT/platforms/macos/build/Release/Dau.app"
RELEASE_DIR="$ROOT/dist"
ZIP_PATH=""   # filled per version
RELEASE_REPO="hapo-nghialuu/dau"

VERSION=""
DRY_RUN=0
SKIP_BUILD=0
ARCH="universal"

usage() {
  cat <<'EOF'
Usage: ./scripts/release.sh VERSION [--dry-run] [--skip-build] [--arch ARCH]

  VERSION     SemVer release version, e.g. 0.2.0 (no leading 'v').
  --dry-run   Print planned steps only — no compile, no publish.
  --skip-build Use an existing app bundle (skip the macOS build).
  --arch ARCH arm64 | x86_64 | universal (default: universal).
              universal builds and packages both slices; the app executable
              is verified with `lipo -info` before packaging.
  -h, --help  Show this help.

Requires (only for a real run):
  bash, semver-ish VERSION, git on branch 'main' with a clean tree,
  cargo + xcodebuild (via scripts/build/macos.sh --adhoc), gh.
  For a universal build: `rustup target add aarch64-apple-darwin
  x86_64-apple-darwin` and lipo (bundled with Xcode command line tools).
  --dry-run skips the lipo/rustup-target checks (no compile, no verify).
EOF
}

semver_regex='^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$'

log() { printf '%s\n' "$*"; }


info() { printf '[release] %s\n' "$*"; }

err() {
  printf '[release][error] %s\n' "$*" >&2
  exit 1
}

run() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf '[dry-run] %s\n' "$*"
  else
    printf '+ %s\n' "$*"
    "$@"
  fi
}

# --- Guards ---------------------------------------------------------------

guard_main_branch() {
  local branch
  branch="$(git branch --show-current)"
  if [[ "$branch" != "main" ]]; then
    err "must run on 'main' branch (current: '${branch}')"
  fi
}

guard_clean_tree() {
  if [[ -n "$(git status --porcelain)" ]]; then
    err "working tree must be clean (uncommitted changes or untracked files present)"
  fi
}

guard_semver() {
  if [[ ! "$VERSION" =~ $semver_regex ]]; then
    err "VERSION '$VERSION' is not valid semver (expected e.g. 0.2.0)"
  fi
}

guard_arch() {
  case "$ARCH" in
    arm64|x86_64|universal) ;;
    *) err "invalid --arch '$ARCH' (expected arm64|x86_64|universal)" ;;
  esac
}

# --- core ------------------------------------------------------------------

resolve_outputs() {
  ZIP="$RELEASE_DIR/Dau-$VERSION.zip"
  ZIP_PATH="$ZIP"
}

plan_paths() {
  info "ROOT=$ROOT"
  info "BUILD_SCRIPT=$BUILD_SCRIPT"
  info "APP_DIR=$APP_DIR"
  info "ZIP_PATH=$ZIP_PATH"
}

validate_build_script() {
  if [[ ! -x "$BUILD_SCRIPT" ]]; then
    err "missing executable build script: $BUILD_SCRIPT"
  fi
}

guard_universal_prereqs() {
  [[ "$ARCH" == "universal" ]] || return 0
  if [[ "$DRY_RUN" -eq 1 ]]; then
    info "--dry-run: skipping lipo/rustup-target checks (no compile or package verification)."
    return 0
  fi
  if ! command -v lipo >/dev/null 2>&1; then
    err "lipo not found (install Xcode command line tools) — required to build/verify universal binaries"
  fi
  if [[ "$SKIP_BUILD" -eq 1 ]]; then
    info "--skip-build: skipping rustup target check (reusing existing app)."
    return 0
  fi
  local targets missing=() t
  targets="$(rustup target list --installed 2>/dev/null || true)"
  for t in aarch64-apple-darwin x86_64-apple-darwin; do
    if ! grep -qx "$t" <<<"$targets"; then
      missing+=("$t")
    fi
  done
  if [[ "${#missing[@]}" -gt 0 ]]; then
    err "universal build requires missing rustup targets: ${missing[*]} (run: rustup target add ${missing[*]})"
  fi
}

verify_app_arch() {
  local exe="$APP_DIR/Contents/MacOS/Dau"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf '[dry-run] lipo -info %s\n' "$exe"
    return 0
  fi
  [[ -f "$exe" ]] || err "missing app executable: $exe"
  local info
  info="$(lipo -info "$exe" 2>/dev/null)" || err "lipo -info failed for $exe"
  info "lipo -info: $info"
  case "$ARCH" in
    universal)
      if [[ "$info" != *arm64* || "$info" != *x86_64* ]]; then
        err "expected universal app (arm64 + x86_64 slices) but got: $info"
      fi
      ;;
    arm64)
      if [[ "$info" != *arm64* ]]; then
        err "expected arm64 app slice but got: $info"
      fi
      ;;
    x86_64)
      if [[ "$info" != *x86_64* ]]; then
        err "expected x86_64 app slice but got: $info"
      fi
      ;;
  esac
}

build_app() {
  if [[ "$SKIP_BUILD" -eq 1 ]]; then
    info "Skipping build (--skip-build); using existing app if present."
    return 0
  fi
  if [[ "$DRY_RUN" -eq 1 ]]; then
    # Show the underlying build plan without compiling.
    "$BUILD_SCRIPT" --adhoc --version "$VERSION" --arch "$ARCH" --dry-run
    return 0
  fi
  run "$BUILD_SCRIPT" --adhoc --version "$VERSION" --arch "$ARCH"
}

require_app() {
  if [[ ! -d "$APP_DIR" ]]; then
    err "expected app bundle missing: $APP_DIR (run a real build first)"
  fi
}

verify_bundle_version() {
  local short build
  [[ -f "$APP_DIR/Contents/Info.plist" ]] || err "missing Info.plist in $APP_DIR"
  short="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_DIR/Contents/Info.plist" 2>/dev/null || true)"
  build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_DIR/Contents/Info.plist" 2>/dev/null || true)"
  info "bundle CFBundleShortVersionString=$short  CFBundleVersion=$build"
  if [[ "$short" != "$VERSION" ]]; then
    err "bundle short version '$short' != release version '$VERSION'"
  fi
}

package_zip() {
  mkdir -p "$RELEASE_DIR"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf '[dry-run] ditto -c -k --keepParent %s %s\n' "$APP_DIR" "$ZIP_PATH"
    return 0
  fi
  rm -f "$ZIP_PATH" "$ZIP_PATH.sha256"
  ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"
  info "zipped: $ZIP_PATH"
}

checksum() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf '[dry-run] shasum -a 256 %s > %s.sha256\n' "$ZIP_PATH" "$ZIP_PATH"
    return 0
  fi
  [[ -f "$ZIP_PATH" ]] || err "zip missing for checksum: $ZIP_PATH"
  (cd "$RELEASE_DIR" && shasum -a 256 "Dau-$VERSION.zip" > "Dau-$VERSION.zip.sha256")
  info "SHA256 written: $ZIP_PATH.sha256"
}

# --- publish (only when NOT dry-run) -----------------------------------------

publish() {
  local gh_tag="v$VERSION"
  info "Publishing release $gh_tag via GitHub CLI."
  run gh release create "$gh_tag" "$ZIP_PATH" "$ZIP_PATH.sha256" \
    --repo "$RELEASE_REPO" \
    --title "Dấu $gh_tag" \
    --notes "macOS build Dau-$VERSION.zip (ad-hoc, no notarization)."

  update_cask_sha
}

update_cask_sha() {
  local cask="$ROOT/Casks/dau.rb"
  local sha file
  file="$RELEASE_DIR/Dau-$VERSION.zip.sha256"
  [[ -f "$file" ]] || err "sha256 file missing: $file"
  sha="$(awk '{print $1}' "$file")"
  info "cask update placeholder: $cask -> sha256 '$sha'"
  if [[ -f "$cask" ]]; then
    sed -i '' -E "s/sha256 \"[0-9a-fA-F]{64}\"/sha256 \"$sha\"/" "$cask"
  fi
}

# --- flags -----------------------------------------------------------------

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --skip-build) SKIP_BUILD=1; shift ;;
    --arch)
      if [[ -z "${2:-}" ]]; then
        echo "Option --arch needs a value (arm64|x86_64|universal)" >&2
        exit 2
      fi
      ARCH="$2"
      shift 2
      ;;
    -h|--help) usage; exit 0 ;;
    -*)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      if [[ -z "$VERSION" ]]; then
        VERSION="$1"
        shift
      else
        echo "Unexpected argument: $1" >&2
        usage >&2
        exit 2
      fi
      ;;
  esac
done

guard_presence() {
  [[ -n "$VERSION" ]] || err "missing VERSION"
}

main() {
  # Resolve before printing paths so dry-run shows correct targets.
  resolve_outputs
  plan_paths

  guard_presence
  guard_semver
  guard_arch
  guard_main_branch
  guard_clean_tree
  validate_build_script
  guard_universal_prereqs

  info "== build (arch=$ARCH) =="
  build_app
  if [[ "$DRY_RUN" -eq 0 ]]; then
    require_app
    verify_bundle_version
  fi
  verify_app_arch

  info "== package =="
  package_zip
  checksum

  if [[ "$DRY_RUN" -eq 0 ]]; then
    info "== publish =="
    publish
  else
    info "Dry run complete — nothing compiled or published."
    info "Artifact plan:"
    printf '  %s\n  %s\n' "$ZIP_PATH" "$ZIP_PATH.sha256"
  fi

  info "done."
}

main "$@"
