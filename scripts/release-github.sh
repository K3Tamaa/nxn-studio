#!/bin/bash
# Publishes the current VERSION on GitHub: repo, tag, release and update feed.
# Usage: ./scripts/release-github.sh [repo-name]
set -euo pipefail
cd "$(dirname "$0")/.."

REPO="${1:-nxn-studio}"
VERSION=$(cat VERSION)
DMG="dist/NXN Studio $VERSION.dmg"

command -v gh >/dev/null || { echo "✗ GitHub CLI manquante : brew install gh"; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "✗ Connectez-vous d'abord : gh auth login"; exit 1; }
[ -f "$DMG" ] || { echo "✗ DMG manquant : ./scripts/package.sh"; exit 1; }
[ -f "$HOME/.nxnstudio/update-keypair.txt" ] || { echo "✗ Clé de signature absente"; exit 1; }

OWNER=$(gh api user --jq .login)
SLUG="$OWNER/$REPO"
TAG="v$VERSION"
KEY_FILE="$HOME/.nxnstudio/update-keypair.txt"
PRIVATE_KEY=$(grep '^private=' "$KEY_FILE" | cut -d= -f2-)
PUBLIC_KEY=$(grep '^public=' "$KEY_FILE" | cut -d= -f2-)
FEED="https://github.com/$SLUG/releases/latest/download/latest.json"
ASSET="https://github.com/$SLUG/releases/download/$TAG/$(basename "$DMG" | sed 's/ /%20/g')"

echo "▸ Dépôt $SLUG…"
if ! gh repo view "$SLUG" >/dev/null 2>&1; then
  gh repo create "$SLUG" --public --description "Client macOS non officiel pour nxnative" --source . --remote origin --push
else
  git remote get-url origin >/dev/null 2>&1 || git remote add origin "https://github.com/$SLUG.git"
  git push -u origin HEAD
fi

echo "▸ Commit et tag…"
git add -A
git diff --cached --quiet || git commit -m "NXN Studio $VERSION"
git tag -f "$TAG" >/dev/null
git push origin "refs/tags/$TAG" --force

echo "▸ Manifeste…"
UPDATE_PRIVATE_KEY="$PRIVATE_KEY" NOTES="$(awk -v v="## $VERSION" '$0==v{f=1;next} /^## /{f=0} f' CHANGELOG.md | sed '/^$/d' | head -12)" \
  ./scripts/publish.sh "https://github.com/$SLUG/releases/download/$TAG"
# The published feed must point at the release asset, not the local folder.
python3 - "$ASSET" <<'PY'
import json,sys
p="dist/latest.json"
d=json.load(open(p))
d["url"]=sys.argv[1]
json.dump(d,open(p,"w"),indent=2,ensure_ascii=False)
print("url ->", sys.argv[1])
PY

echo "▸ Release GitHub…"
gh release view "$TAG" --repo "$SLUG" >/dev/null 2>&1 && gh release delete "$TAG" --repo "$SLUG" --yes
gh release create "$TAG" --repo "$SLUG" --title "NXN Studio $VERSION" --notes-file <(awk -v v="## $VERSION" '$0==v{f=1;next} /^## /{f=0} f' CHANGELOG.md) \
  "$DMG" "dist/latest.json"

echo ""
echo "✓ Release publiée : https://github.com/$SLUG/releases/tag/$TAG"
echo "  flux : $FEED"
echo ""
echo "Reconstruis le client avec le flux :"
echo "  UPDATE_FEED=\"$FEED\" UPDATE_PUBLIC_KEY=\"$PUBLIC_KEY\" ./scripts/package.sh"
