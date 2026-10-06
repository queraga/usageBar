#!/bin/bash
# Builds a Release UsageBar.app into release/.
# Optional environment overrides:
#   VERSION            marketing version written into Info.plist (default: project value)
#   BUILD_NUMBER       CFBundleVersion (default: project value)
#   SIGN_IDENTITY      codesign identity, "-" for ad-hoc (default: -)
set -euo pipefail
cd "$(dirname "$0")/.."

SIGN_IDENTITY="${SIGN_IDENTITY:--}"
SETTINGS=(ONLY_ACTIVE_ARCH=NO "CODE_SIGN_IDENTITY=$SIGN_IDENTITY")
if [[ -n "${VERSION:-}" ]]; then SETTINGS+=("MARKETING_VERSION=$VERSION"); fi
if [[ -n "${BUILD_NUMBER:-}" ]]; then SETTINGS+=("CURRENT_PROJECT_VERSION=$BUILD_NUMBER"); fi
if [[ "$SIGN_IDENTITY" != "-" ]]; then
  # Distribution builds need a hardened runtime and a secure timestamp to notarize.
  SETTINGS+=(CODE_SIGN_STYLE=Manual ENABLE_HARDENED_RUNTIME=YES OTHER_CODE_SIGN_FLAGS="--timestamp --options=runtime")
  if [[ -n "${DEVELOPMENT_TEAM:-}" ]]; then SETTINGS+=("DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM"); fi
fi

xcodebuild -project UsageBar.xcodeproj -scheme UsageBar -configuration Release \
  -derivedDataPath build/ReleaseDerivedData -destination 'generic/platform=macOS' \
  "${SETTINGS[@]}" build
rm -rf release/UsageBar.app
mkdir -p release
ditto build/ReleaseDerivedData/Build/Products/Release/UsageBar.app release/UsageBar.app
codesign --verify --deep --strict release/UsageBar.app
