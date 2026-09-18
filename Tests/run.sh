#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_WORK="$(mktemp -d)"
trap 'rm -rf "$TEST_WORK"' EXIT
mkdir -p "$TEST_WORK/fakes" build/test-module-cache
for mode in good init-timeout request-timeout malformed auth exit; do
  ln -s "$PWD/Tests/fake-codex.py" "$TEST_WORK/fakes/$mode"
done
: > "$TEST_WORK/state"
# The first provider spawn is timed, so pay the interpreter's cold start up front.
/usr/bin/python3 -c 'import json,sys,time,os,signal;from pathlib import Path' || {
  echo "Tests need /usr/bin/python3" >&2; exit 1
}
xcrun swiftc -parse-as-library -module-cache-path "$PWD/build/test-module-cache" \
  ChatGPTUsage/Models/UsageModels.swift ChatGPTUsage/Services/UsageProvider.swift \
  ChatGPTUsage/Services/CodexUsageProvider.swift ChatGPTUsage/Store/UsageStore.swift \
  Tests/ProviderValidation.swift -o "$TEST_WORK/validate"
USAGE_TEST_STATE="$TEST_WORK/state" \
  USAGE_TEST_TIME_SCALE="${USAGE_TEST_TIME_SCALE:-1}" \
  "$TEST_WORK/validate" "$TEST_WORK/fakes"
if [[ "${1:-}" == "--live" ]]; then "$TEST_WORK/validate" --live; fi
