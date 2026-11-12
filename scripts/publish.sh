#!/bin/bash
# Build dist/latest.json for the current VERSION.
# Usage: UPDATE_PRIVATE_KEY=<base64> ./scripts/publish.sh <releases-base-url>
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(cat VERSION)
DMG="dist/NXN Studio $VERSION.dmg"
[ -f "$DMG" ] || { echo "✗ DMG manquant : lancez ./scripts/package.sh"; exit 1; }
[ -n "${UPDATE_PRIVATE_KEY:-}" ] || { echo "✗ UPDATE_PRIVATE_KEY manquante"; exit 1; }
BASE_URL="${1:?URL de base des releases (ex. https://github.com/toi/nxn-studio/releases/download/v1.2.0)}"

SIG=$("dist/NXN Studio.app/Contents/MacOS/NXNStudio" --sign-update "$DMG" "$UPDATE_PRIVATE_KEY")
SIZE=$(stat -f%z "$DMG")
SHA=$(shasum -a 256 "$DMG" | cut -d' ' -f1)
FILE=$(basename "$DMG" | sed 's/ /%20/g')
NOTES="${NOTES:-Correctifs et améliorations.}"

cat > dist/latest.json <<EOF
{
  "version": "$VERSION",
  "build": "$(date +%Y%m%d%H%M)",
  "url": "$BASE_URL/$FILE",
  "size": $SIZE,
  "sha256": "$SHA",
  "signature": "$SIG",
  "notes": "$NOTES",
  "publishedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

echo "✓ dist/latest.json"
echo "  version $VERSION · $SIZE octets · sha256 ${SHA:0:16}…"
echo ""
echo "Publie le DMG et latest.json, puis reconstruis avec :"
echo "  UPDATE_FEED=\"<url de latest.json>\" \\"
echo "  UPDATE_PUBLIC_KEY=\"$(grep '^public=' "$HOME/.nxnstudio/update-keypair.txt" | cut -d= -f2-)\" \\"
echo "  ./scripts/package.sh"
