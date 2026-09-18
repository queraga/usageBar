#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
xcodebuild -project UsageBar.xcodeproj -scheme UsageBar -configuration Release \
  -derivedDataPath build/ReleaseDerivedData -destination 'generic/platform=macOS' \
  ONLY_ACTIVE_ARCH=NO CODE_SIGN_IDENTITY=- build
mkdir -p release
ditto build/ReleaseDerivedData/Build/Products/Release/UsageBar.app release/UsageBar.app
codesign --verify --deep --strict release/UsageBar.app
