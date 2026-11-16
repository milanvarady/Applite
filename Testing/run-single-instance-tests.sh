#!/bin/bash
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/applite-single-instance-tests.XXXXXX")"
trap 'rm -f "$test_dir/SingleInstanceTests"; rmdir "$test_dir"' EXIT

xcrun swiftc -parse-as-library -swift-version 6 -target "$(uname -m)-apple-macos14.0" \
    "$repo/Applite/Core/Infrastructure/SingleInstanceLock.swift" \
    "$repo/Applite/Features/Settings/SettingsNavigation.swift" \
    "$repo/Applite/Core/CaskCore/CaskProgressState.swift" \
    "$repo/Applite/Core/Models/AppStatusSummary.swift" \
    "$repo/Applite/Core/Models/CaskAdditionalInfo.swift" \
    "$repo/Applite/Core/Models/CaskDTO.swift" \
    "$repo/Testing/SingleInstanceTests.swift" \
    -o "$test_dir/SingleInstanceTests"
"$test_dir/SingleInstanceTests"
