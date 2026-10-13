#!/bin/bash
# Packages release/UsageBar.app into a distributable DMG with an /Applications drop target.
# Usage: Scripts/make-dmg.sh <version> [output-dmg]
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: make-dmg.sh <version> [output-dmg]}"
DMG="${2:-release/UsageBar-$VERSION.dmg}"
APP="release/UsageBar.app"

[[ -d "$APP" ]] || { echo "Missing $APP - run Scripts/build.sh first" >&2; exit 1; }

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP" "$STAGING/UsageBar.app"
ln -s /Applications "$STAGING/Applications"

mkdir -p "$(dirname "$DMG")"
rm -f "$DMG"
hdiutil create -volname "UsageBar $VERSION" -srcfolder "$STAGING" \
  -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
hdiutil verify "$DMG" >/dev/null
echo "$DMG"
