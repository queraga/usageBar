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
xcrun swiftc -parse-as-library -module-cache-path "$PWD/build/test-module-cache" \
  ChatGPTUsage/Models/UsageModels.swift ChatGPTUsage/Services/UsageProvider.swift \
  ChatGPTUsage/Services/CodexUsageProvider.swift ChatGPTUsage/Store/UsageStore.swift \
  Tests/ProviderValidation.swift -o "$TEST_WORK/validate"
USAGE_TEST_STATE="$TEST_WORK/state" "$TEST_WORK/validate" "$TEST_WORK/fakes"
if [[ "${1:-}" == "--live" ]]; then "$TEST_WORK/validate" --live; fi
