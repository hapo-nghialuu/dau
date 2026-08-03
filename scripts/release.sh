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
#   ./scripts/release.sh -h | --help
#
# Notes:
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

usage() {
  cat <<'EOF'
Usage: ./scripts/release.sh VERSION [--dry-run] [--skip-build]

  VERSION     SemVer release version, e.g. 0.2.0 (no leading 'v').
  --dry-run   Print planned steps only — no compile, no publish.
  --skip-build Use an existing app bundle (skip the macOS build).
  -h, --help  Show this help.

Requires (only for a real run):
  bash, semver-ish VERSION, git on branch 'main' with a clean tree,
  cargo + xcodebuild (via scripts/build/macos.sh --adhoc), gh.
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

build_app() {
  if [[ "$SKIP_BUILD" -eq 1 ]]; then
    info "Skipping build (--skip-build); using existing app if present."
    return 0
  fi
  if [[ "$DRY_RUN" -eq 1 ]]; then
    # Show the underlying build plan without compiling.
    "$BUILD_SCRIPT" --adhoc --version "$VERSION" --dry-run
    return 0
  fi
  run "$BUILD_SCRIPT" --adhoc --version "$VERSION"
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
  info "Publishing release $gh_tag (manual push/tag expected upstream)."
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
  guard_main_branch
  guard_clean_tree
  validate_build_script

  info "== build =="
  build_app
  if [[ "$DRY_RUN" -eq 0 ]]; then
    require_app
    verify_bundle_version
  fi

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
