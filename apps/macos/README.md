# Rift for macOS

The macOS app is a SwiftUI executable package targeting macOS 26 and the native
Liquid Glass design system.

On a Mac with Xcode 26 or newer:

```sh
cd apps/macos
swift run RiftMac
```

You can also open `Package.swift` in Xcode to run, debug, sign, and archive the
app. The current vertical slice opens a local repository and displays its
branch, working-copy changes, and recent commits.

Create a signed (ad-hoc by default) app bundle and ZIP:

```sh
./scripts/package-macos.sh
```

Set `RIFT_CODESIGN_IDENTITY` to a Developer ID Application identity for a
distribution build. Notarization credentials are intentionally supplied only
through the release environment, never stored in the repository.
