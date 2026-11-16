#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/applite-font-category-tests.XXXXXX")"
trap 'rm -f "$test_dir/FontCaskMetadataTests"; rmdir "$test_dir"' EXIT

swiftc \
    "$repo/Applite/Core/Models/CaskDTO.swift" \
    "$repo/Testing/FontCaskMetadataTests.swift" \
    -o "$test_dir/FontCaskMetadataTests"
"$test_dir/FontCaskMetadataTests"
