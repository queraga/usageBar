#!/bin/bash
# Prints Markdown release notes for a version: a changelog built from the commits
# since the previous tag, install steps, and asset checksums.
# Usage: Scripts/release-notes.sh <version> [asset-dir]
# Environment: NOTARIZED=true drops the Gatekeeper workaround note.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: release-notes.sh <version> [asset-dir]}"
ASSET_DIR="${2:-release}"

# A draft release has no git tag yet, so fall back to HEAD; a published one is tagged.
if RANGE_END="$(git rev-parse --verify --quiet "refs/tags/$VERSION^{commit}")"; then
  # Nearest tag in this tag's ancestry, so out-of-order patch releases still diff correctly.
  PREVIOUS="$(git describe --tags --abbrev=0 "$RANGE_END^" 2>/dev/null || true)"
  COMPARE_END="$VERSION"
else
  RANGE_END="$(git rev-parse HEAD)"
  PREVIOUS="$(git describe --tags --abbrev=0 "$RANGE_END" 2>/dev/null || true)"
  COMPARE_END="$RANGE_END"  # the tag appears only when the draft is published
fi
[[ "$PREVIOUS" != "$VERSION" ]] || PREVIOUS=""
if [[ -n "$PREVIOUS" ]]; then RANGE="$PREVIOUS..$RANGE_END"; else RANGE="$RANGE_END"; fi

CHANGES="$(git log --no-merges --reverse --pretty='- %s' "$RANGE")"
[[ -n "$CHANGES" ]] || CHANGES="- Maintenance release."
printf '%s\n\n' "$CHANGES"

cat <<'INSTALL'
## Install

1. Download `UsageBar.dmg` below.
2. Open it and drag **UsageBar** to **Applications**.
3. Launch UsageBar and look for it in the menu bar.

Requires macOS 13 or later and an authenticated OpenAI/Codex environment.
INSTALL

if [[ "${NOTARIZED:-false}" != "true" ]]; then
  cat <<'GATEKEEPER'

This build is ad-hoc signed and not notarized. If Gatekeeper blocks the first launch,
open **System Settings → Privacy & Security** and choose **Open Anyway** for UsageBar.
Do not disable Gatekeeper.
GATEKEEPER
fi

ASSETS=()
for asset in "$ASSET_DIR"/*.dmg "$ASSET_DIR"/*.zip; do
  [[ -f "$asset" ]] && ASSETS+=("$(basename "$asset")")
done
if (( ${#ASSETS[@]} )); then
  printf '\n## Checksums\n\n```\n'
  (cd "$ASSET_DIR" && shasum -a 256 "${ASSETS[@]}")
  printf '```\n'
fi

if [[ -n "$PREVIOUS" ]]; then
  REPO="${GITHUB_REPOSITORY:-queraga/usageBar}"
  printf '\n**Full changelog**: https://github.com/%s/compare/%s...%s\n' "$REPO" "$PREVIOUS" "$COMPARE_END"
fi
