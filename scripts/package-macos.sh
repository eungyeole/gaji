#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
package_path="$project_root/apps/macos"
output_root="$project_root/dist/macos"
app_bundle="$output_root/Rift.app"
info_plist="$app_bundle/Contents/Info.plist"

rm -rf "$app_bundle" "$output_root/Rift-macOS.zip"

if [ "${RIFT_MACOS_UNIVERSAL:-0}" = "1" ]; then
    rustup target add aarch64-apple-darwin x86_64-apple-darwin
    cargo build --manifest-path "$project_root/Cargo.toml" -p rift-ffi --release --target aarch64-apple-darwin
    cargo build --manifest-path "$project_root/Cargo.toml" -p rift-ffi --release --target x86_64-apple-darwin
    mkdir -p "$project_root/target/release"
    lipo -create \
        "$project_root/target/aarch64-apple-darwin/release/librift_ffi.a" \
        "$project_root/target/x86_64-apple-darwin/release/librift_ffi.a" \
        -output "$project_root/target/release/librift_ffi.a"
    swift build -c release --package-path "$package_path" --arch arm64 --arch x86_64
    binary_path=$(swift build -c release --package-path "$package_path" --arch arm64 --arch x86_64 --show-bin-path)
else
    cargo build --manifest-path "$project_root/Cargo.toml" -p rift-ffi --release
    swift build -c release --package-path "$package_path"
    binary_path=$(swift build -c release --package-path "$package_path" --show-bin-path)
fi

mkdir -p "$app_bundle/Contents/MacOS" "$app_bundle/Contents/Resources" "$app_bundle/Contents/Frameworks"
ditto "$binary_path/RiftMac" "$app_bundle/Contents/MacOS/RiftMac"
ditto "$package_path/Resources/Info.plist" "$info_plist"

sparkle_framework=$(find "$package_path/.build/artifacts" -type d -name Sparkle.framework -print -quit)
if [ -z "$sparkle_framework" ]; then
    echo "Sparkle.framework was not found in SwiftPM artifacts" >&2
    exit 1
fi
ditto "$sparkle_framework" "$app_bundle/Contents/Frameworks/Sparkle.framework"

if ! otool -l "$app_bundle/Contents/MacOS/RiftMac" | grep -A2 LC_RPATH | grep -q '@executable_path/../Frameworks'; then
    install_name_tool -add_rpath '@executable_path/../Frameworks' "$app_bundle/Contents/MacOS/RiftMac"
fi

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${RIFT_VERSION:-0.1.0}" "$info_plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${RIFT_BUILD_NUMBER:-1}" "$info_plist"
if [ -n "${SPARKLE_PUBLIC_ED_KEY:-}" ]; then
    /usr/libexec/PlistBuddy -c "Set :SUPublicEDKey $SPARKLE_PUBLIC_ED_KEY" "$info_plist"
elif [ "${RIFT_REQUIRE_UPDATE_SIGNING:-0}" = "1" ]; then
    echo "SPARKLE_PUBLIC_ED_KEY is required for a distributable build" >&2
    exit 1
fi

if [ -n "${RIFT_CODESIGN_IDENTITY:-}" ]; then
    codesign --force --deep --options runtime --timestamp --sign "$RIFT_CODESIGN_IDENTITY" "$app_bundle"
else
    codesign --force --deep --sign - "$app_bundle"
fi

codesign --verify --deep --strict "$app_bundle"
ditto -c -k --sequesterRsrc --keepParent "$app_bundle" "$output_root/Rift-macOS.zip"
