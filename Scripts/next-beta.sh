#!/bin/bash
# Prints the next unused beta version for a base version: 0.2.0 -> 0.2.0-beta1, then -beta2...
# Usage: Scripts/next-beta.sh <base-version> [-]
# Existing versions are read from stdin (one per line) when '-' is passed, otherwise from this
# repo's releases - drafts included, since betas are drafts - and its git tags.
set -euo pipefail
cd "$(dirname "$0")/.."

BASE="${1:?usage: next-beta.sh <base-version> [-]}"
BASE="${BASE%%-*}"  # tolerate being handed a version that already carries a suffix
if [[ ! "$BASE" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "'$BASE' is not a semantic version like 1.2.3" >&2
  exit 1
fi

if [[ "${2:-}" == "-" ]]; then
  EXISTING="$(cat)"
else
  EXISTING="$(
    gh release list --limit 200 --json tagName --jq '.[].tagName' 2>/dev/null || true
    git tag -l
  )"
fi

HIGHEST=0
PATTERN="^${BASE//./\\.}-beta([0-9]+)\$"
while read -r NAME; do
  [[ "$NAME" =~ $PATTERN ]] || continue
  if (( BASH_REMATCH[1] > HIGHEST )); then HIGHEST="${BASH_REMATCH[1]}"; fi
done <<< "$EXISTING"

echo "$BASE-beta$(( HIGHEST + 1 ))"
