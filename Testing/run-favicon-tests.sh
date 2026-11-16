#!/bin/bash
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/applite-favicon-tests.XXXXXX")"
trap 'rm -f "$test_dir/FaviconResolverTests"; rmdir "$test_dir"' EXIT

xcrun swiftc -parse-as-library -swift-version 6 -target "$(uname -m)-apple-macos14.0" \
    "$repo/Applite/Core/Infrastructure/FaviconResolver.swift" \
    "$repo/Testing/FaviconResolverTests.swift" \
    -o "$test_dir/FaviconResolverTests"
"$test_dir/FaviconResolverTests" "$@"
