#!/bin/bash
# Prints the app's marketing version, the single source of truth for release numbers.
# Bump MARKETING_VERSION in UsageBar.xcodeproj to ship a new version.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=""
if command -v xcodebuild >/dev/null 2>&1; then
  # Tolerates a Command Line Tools-only machine, where xcodebuild exists but cannot run.
  VERSION="$(xcodebuild -project UsageBar.xcodeproj -scheme UsageBar -configuration Release \
    -showBuildSettings 2>/dev/null | awk -F' = ' '/ MARKETING_VERSION = /{print $2; exit}' || true)"
fi
if [[ -z "$VERSION" ]]; then
  # No Xcode (or a scheme-less checkout): read the project file directly.
  VERSION="$(sed -n 's/.*MARKETING_VERSION = \([^;]*\);.*/\1/p' \
    UsageBar.xcodeproj/project.pbxproj | head -1)"
fi

VERSION="${VERSION//[[:space:]]/}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-.+)?$ ]]; then
  echo "Could not read a semantic MARKETING_VERSION from UsageBar.xcodeproj (got '$VERSION')" >&2
  exit 1
fi
echo "$VERSION"
