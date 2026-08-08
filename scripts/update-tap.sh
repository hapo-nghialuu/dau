#!/usr/bin/env bash
# Update homebrew-tap with new cask version
# Usage: scripts/update-tap.sh 0.1.5 <sha256>
set -euo pipefail

VERSION="${1:-}"
SHA256="${2:-}"

if [[ -z "$VERSION" ]] || [[ -z "$SHA256" ]]; then
  echo "Usage: $0 <version> <sha256>" >&2
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TAP_REPO="hapo-nghialuu/homebrew-tap"

# Find or clone tap repo
TAP_DIR=$(brew --repository "$TAP_REPO" 2>/dev/null || echo "")
if [[ -z "$TAP_DIR" ]] || [[ ! -d "$TAP_DIR" ]]; then
  TAP_DIR="$REPO_ROOT/.homebrew-tap"
  if [[ ! -d "$TAP_DIR" ]]; then
    echo "==> Cloning $TAP_REPO"
    git clone "https://github.com/${TAP_REPO}.git" "$TAP_DIR"
  fi
fi

echo "==> Updating tap cask to v${VERSION}"
git -C "$TAP_DIR" pull --ff-only

CASK_TAP="$TAP_DIR/Casks/dau.rb"

# Update version and sha256
python3 - "$CASK_TAP" "$VERSION" "$SHA256" <<'PY'
import re, sys
path, version, sha = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path) as f:
    content = f.read()
content = re.sub(r'version "\d+\.\d+\.\d+"', f'version "{version}"', content, count=1)
content = re.sub(r'sha256 "[a-f0-9]{64}"', f'sha256 "{sha}"', content, count=1)
with open(path, 'w') as f:
    f.write(content)
PY

git -C "$TAP_DIR" add Casks/dau.rb
git -C "$TAP_DIR" commit -m "chore: bump dau to ${VERSION}"
git -C "$TAP_DIR" push origin main

echo "==> Done. Tap updated:"
echo "    Install: brew install hapo-nghialuu/tap/dau"
echo "    Upgrade: brew upgrade hapo-nghialuu/tap/dau"
