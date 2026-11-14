#!/bin/bash
set -euo pipefail

# Use an existing unsigned Debug build; do not launch the app or touch real Homebrew.
derived_data="${1:?Usage: bash Testing/run-external-install-tests.sh /path/to/DerivedData}"
repo="$(cd "$(dirname "$0")/.." && pwd)"
products="$derived_data/Build/Products/Debug"
sqlite="$derived_data/SourcePackages/checkouts/GRDB.swift/Sources/GRDBSQLite"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/applite-external-tests.XXXXXX")"
bundle="$test_dir/ExternalInstallTests.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
cleanup() {
    rm -f "$bundle/Contents/MacOS/ExternalInstallTests" "$bundle/Contents/Info.plist" "$bundle/Contents/Resources/askpass.js"
    rmdir "$bundle/Contents/MacOS" "$bundle/Contents/Resources" "$bundle/Contents" "$bundle" "$test_dir"
}
trap cleanup EXIT
cp "$products/Applite.app/Contents/Resources/askpass.js" "$bundle/Contents/Resources/askpass.js"

plutil -create xml1 "$bundle/Contents/Info.plist"
plutil -insert CFBundleIdentifier -string dev.applite.ExternalInstallTests "$bundle/Contents/Info.plist"
plutil -insert CFBundleExecutable -string ExternalInstallTests "$bundle/Contents/Info.plist"
plutil -insert CFBundlePackageType -string APPL "$bundle/Contents/Info.plist"

xcrun swiftc -parse-as-library -swift-version 6 \
    -I "$products" -I "$sqlite" -F "$products" -F "$products/PackageFrameworks" \
    "$repo/Testing/ExternalInstallTests.swift" \
    "$products/Applite.app/Contents/MacOS/Applite.debug.dylib" \
    -Xlinker -rpath -Xlinker "$products/Applite.app/Contents/MacOS" \
    -Xlinker -rpath -Xlinker "$products/Applite.app/Contents/Frameworks" \
    -o "$bundle/Contents/MacOS/ExternalInstallTests"
"$bundle/Contents/MacOS/ExternalInstallTests"
