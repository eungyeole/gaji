#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
package_path="$project_root/apps/macos"
output_root="$project_root/dist/macos"
app_bundle="$output_root/Rift.app"

cargo build --manifest-path "$project_root/Cargo.toml" -p rift-ffi --release
swift build -c release --package-path "$package_path"
binary_path=$(swift build -c release --package-path "$package_path" --show-bin-path)

mkdir -p "$app_bundle/Contents/MacOS" "$app_bundle/Contents/Resources"
ditto "$binary_path/RiftMac" "$app_bundle/Contents/MacOS/RiftMac"
ditto "$package_path/Resources/Info.plist" "$app_bundle/Contents/Info.plist"

if [ -n "${RIFT_CODESIGN_IDENTITY:-}" ]; then
    codesign --force --deep --options runtime --timestamp --sign "$RIFT_CODESIGN_IDENTITY" "$app_bundle"
else
    codesign --force --deep --sign - "$app_bundle"
fi

ditto -c -k --keepParent "$app_bundle" "$output_root/Rift-macOS.zip"
codesign --verify --deep --strict "$app_bundle"
