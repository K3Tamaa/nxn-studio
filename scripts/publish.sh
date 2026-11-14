#!/bin/bash
# Build dist/latest.json for the current VERSION.
# Usage: UPDATE_PRIVATE_KEY=<base64> ./scripts/publish.sh <releases-base-url>
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(cat VERSION)
if [ -f "$HOME/.nxnstudio/update-keypair.txt" ]; then
  chmod 600 "$HOME/.nxnstudio/update-keypair.txt"
fi
DMG="dist/NXN Studio $VERSION.dmg"
[ -f "$DMG" ] || { echo "✗ DMG manquant : lancez ./scripts/package.sh"; exit 1; }
[ -n "${UPDATE_PRIVATE_KEY:-}" ] || { echo "✗ UPDATE_PRIVATE_KEY manquante"; exit 1; }
BASE_URL="${1:?URL de base des releases (ex. https://github.com/toi/nxn-studio/releases/download/v1.2.0)}"

[ -x .build/debug/NXNStudio ] || swift build >/dev/null
# The private key travels through stdin, never argv.
SIG=$(printf '%s' "$UPDATE_PRIVATE_KEY" | .build/debug/NXNStudio --sign-update "$DMG" -)
SIZE=$(stat -f%z "$DMG")
SHA=$(shasum -a 256 "$DMG" | cut -d' ' -f1)
FILE=$(basename "$DMG" | sed 's/ /%20/g')
NOTES="${NOTES:-Correctifs et améliorations.}"

python3 - "$VERSION" "$BASE_URL/$FILE" "$SIZE" "$SHA" "$SIG" "$NOTES" <<'PY'
import datetime
import json
import sys

version, url, size, sha, sig, notes = sys.argv[1:7]
json.dump({
    "version": version,
    "build": datetime.datetime.now().strftime("%Y%m%d%H%M"),
    "url": url,
    "size": int(size),
    "sha256": sha,
    "signature": sig,
    "notes": notes.strip(),
    "publishedAt": datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
}, open("dist/latest.json", "w"), indent=2, ensure_ascii=False)
PY

echo "✓ dist/latest.json"
echo "  version $VERSION · $SIZE octets · sha256 ${SHA:0:16}…"
echo ""
echo "Publie le DMG et latest.json, puis reconstruis avec :"
echo "  UPDATE_FEED=\"<url de latest.json>\" \\"
echo "  UPDATE_PUBLIC_KEY=\"$(grep '^public=' "$HOME/.nxnstudio/update-keypair.txt" 2>/dev/null | cut -d= -f2-)\" \\"
echo "  ./scripts/package.sh"
