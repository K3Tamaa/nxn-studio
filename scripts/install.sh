#!/bin/bash
# Install NXN Studio into ~/Applications.
set -euo pipefail
cd "$(dirname "$0")/.."
[ -d "dist/NXN Studio.app" ] || ./scripts/package.sh
mkdir -p "$HOME/Applications"
rm -rf "$HOME/Applications/NXN Studio.app"
cp -R "dist/NXN Studio.app" "$HOME/Applications/"
# A downloaded bundle carries the quarantine flag; this client is not
# notarised yet, so clear it for the copy the user just installed.
xattr -dr com.apple.quarantine "$HOME/Applications/NXN Studio.app" 2>/dev/null || true
echo "✓ installé dans ~/Applications/NXN Studio.app"
open "$HOME/Applications/NXN Studio.app"
