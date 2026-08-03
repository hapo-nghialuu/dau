#!/usr/bin/env bash
# check-metadata.sh — verify product metadata is consistent across the repo.
# Portable bash (macOS + Linux). No GNU-only flags.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

EXPECTED_VERSION="0.1.3"
EXPECTED_NAME="Dấu"
EXPECTED_LICENSE="MIT"
EXPECTED_REPO="https://github.com/hapo-nghialuu/dau"
EXPECTED_ID="dau"

PASS=0
FAIL=0

pass() {
  echo "PASS  $1"
  PASS=$((PASS + 1))
}

fail() {
  echo "FAIL  $1"
  FAIL=$((FAIL + 1))
}

# file_contains FILE PATTERN LABEL
file_contains() {
  local file="$1"
  local pattern="$2"
  local label="$3"
  if [[ ! -f "$file" ]]; then
    fail "$label (missing file: $file)"
    return
  fi
  if grep -q -- "$pattern" "$file"; then
    pass "$label"
  else
    fail "$label (pattern not found in $file: $pattern)"
  fi
}

echo "=== Dấu metadata check ==="
echo "version=$EXPECTED_VERSION  name=$EXPECTED_NAME  license=$EXPECTED_LICENSE"
echo "repo=$EXPECTED_REPO  id=$EXPECTED_ID"
echo

# --- core/Cargo.toml ---
file_contains "core/Cargo.toml" 'name = "dau-core"' \
  "core/Cargo.toml: package name dau-core"
file_contains "core/Cargo.toml" "version = \"${EXPECTED_VERSION}\"" \
  "core/Cargo.toml: version ${EXPECTED_VERSION}"
file_contains "core/Cargo.toml" "license = \"${EXPECTED_LICENSE}\"" \
  "core/Cargo.toml: license ${EXPECTED_LICENSE}"
file_contains "core/Cargo.toml" "repository = \"${EXPECTED_REPO}\"" \
  "core/Cargo.toml: repository URL"
file_contains "core/Cargo.toml" "${EXPECTED_NAME}" \
  "core/Cargo.toml: display name ${EXPECTED_NAME}"

# --- platforms/linux/CMakeLists.txt ---
file_contains "platforms/linux/CMakeLists.txt" "VERSION ${EXPECTED_VERSION}" \
  "CMakeLists.txt: project VERSION ${EXPECTED_VERSION}"
file_contains "platforms/linux/CMakeLists.txt" "${EXPECTED_NAME}" \
  "CMakeLists.txt: display name ${EXPECTED_NAME}"

# --- platforms/linux/data/dau.conf ---
file_contains "platforms/linux/data/dau.conf" "Name=${EXPECTED_NAME}" \
  "dau.conf: Name=${EXPECTED_NAME}"
file_contains "platforms/linux/data/dau.conf" "Addon=${EXPECTED_ID}" \
  "dau.conf: Addon=${EXPECTED_ID}"
file_contains "platforms/linux/data/dau.conf" "Icon=${EXPECTED_ID}" \
  "dau.conf: Icon=${EXPECTED_ID}"

# --- platforms/linux/data/dau-addon.conf ---
file_contains "platforms/linux/data/dau-addon.conf" "Name=${EXPECTED_NAME}" \
  "dau-addon.conf: Name=${EXPECTED_NAME}"
file_contains "platforms/linux/data/dau-addon.conf" "Version=${EXPECTED_VERSION}" \
  "dau-addon.conf: Version=${EXPECTED_VERSION}"
file_contains "platforms/linux/data/dau-addon.conf" "Library=lib${EXPECTED_ID}" \
  "dau-addon.conf: Library=lib${EXPECTED_ID}"

# --- README.md ---
file_contains "README.md" "${EXPECTED_NAME}" \
  "README.md: display name ${EXPECTED_NAME}"
file_contains "README.md" "${EXPECTED_VERSION}" \
  "README.md: version ${EXPECTED_VERSION}"
file_contains "README.md" "${EXPECTED_LICENSE}" \
  "README.md: license ${EXPECTED_LICENSE}"
file_contains "README.md" "${EXPECTED_REPO}" \
  "README.md: repository URL"

# --- LICENSE file ---
if [[ -f LICENSE ]]; then
  if grep -qi 'MIT License' LICENSE; then
    pass "LICENSE: MIT License"
  else
    fail "LICENSE: expected MIT License header"
  fi
else
  fail "LICENSE: file missing"
fi

# --- SPDX headers on C++ sources (platforms/linux/src) ---
SPDX_OK=1
for f in platforms/linux/src/*.cpp platforms/linux/src/*.h; do
  [[ -f "$f" ]] || continue
  if ! grep -q 'SPDX-License-Identifier: MIT' "$f"; then
    fail "SPDX missing: $f"
    SPDX_OK=0
  fi
done
if [[ "$SPDX_OK" -eq 1 ]]; then
  pass "platforms/linux/src: all sources have SPDX MIT header"
fi

echo
echo "=== Summary: ${PASS} PASS, ${FAIL} FAIL ==="
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
exit 0
