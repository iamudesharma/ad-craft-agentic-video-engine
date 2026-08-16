#!/usr/bin/env bash
# Installs the PocketBase binary into backend/pocketbase/ (project-local, no global install).
# Usage: ./scripts/install_pocketbase.sh [version]
set -euo pipefail

VERSION="${1:-v0.39.11}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Default: project-local. Override to install elsewhere, e.g. PB_DEST_DIR="$HOME/bin"
DEST_DIR="${PB_DEST_DIR:-$ROOT/backend/pocketbase}"
BIN="$DEST_DIR/pocketbase"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

case "$(uname -s)-$(uname -m)" in
  Darwin-arm64)  ASSET="pocketbase_${VERSION#v}_darwin_arm64.zip" ;;
  Darwin-x86_64) ASSET="pocketbase_${VERSION#v}_darwin_amd64.zip" ;;
  Linux-x86_64)  ASSET="pocketbase_${VERSION#v}_linux_amd64.zip" ;;
  Linux-aarch64) ASSET="pocketbase_${VERSION#v}_linux_arm64.zip" ;;
  *) echo "Unsupported platform: $(uname -s)-$(uname -m)" >&2; exit 1 ;;
esac

URL="https://github.com/pocketbase/pocketbase/releases/download/$VERSION/$ASSET"
echo "Downloading $URL"
curl -sL -o "$TMP/$ASSET" "$URL"
curl -sL -o "$TMP/checksums.txt" "https://github.com/pocketbase/pocketbase/releases/download/$VERSION/checksums.txt"

expected="$(grep "$ASSET" "$TMP/checksums.txt" | awk '{print $1}')"
actual="$(shasum -a 256 "$TMP/$ASSET" | awk '{print $1}')"
if [ -z "$expected" ] || [ "$expected" != "$actual" ]; then
  echo "checksum verification failed" >&2
  exit 1
fi
echo "checksum OK"

unzip -o "$TMP/$ASSET" -d "$TMP" > /dev/null
chmod +x "$TMP/pocketbase"
mkdir -p "$DEST_DIR"
mv "$TMP/pocketbase" "$BIN"

echo "Installed: $BIN"
"$BIN" --version
