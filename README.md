# Rift

**A native Git workspace for macOS, backed by a shared Rust core.**

Rift keeps Git history, branches, changes, stashes, and diffs in one focused desktop workspace. The macOS app uses SwiftUI and AppKit so navigation, materials, menus, keyboard behavior, and window restoration feel at home on the platform. Git behavior lives in a reusable Rust core that also powers the early Windows client and the development CLI.

> Rift is in active development. macOS 26 is the current product focus. The Windows app is an early WinUI foundation and does not yet have feature or interface parity with macOS.

[Product site](https://eungyeole.github.io/rift/) · [Product direction](docs/PRODUCT.md) · [macOS notes](apps/macos/README.md) · [Windows status](apps/windows/README.md)

## What is working

### Native macOS workspace

- Restore multiple repository tabs between launches.
- Browse local and remote branches, worktrees, and stashes from the sidebar.
- Search branches and switch branches by double-clicking.
- Read compact, lane-based commit history with refs and author avatars.
- Inspect commit and stash files in the inspector, then open a structured diff.
- Stage, unstage, and discard files or individual hunks.
- Create commits with amend, signing, and sign-off options.
- Fetch, pull with merge/rebase/fast-forward-only strategies, and push.
- Create, rename, switch, merge, rebase, and delete branches.
- Run cherry-pick, revert, reset, tags, remotes, worktrees, and submodule flows.
- Detect conflicts, choose either side, edit merge content, continue, or abort.
- Stash, apply, pop, inspect, and drop saved work.

Rift delegates Git execution to the installed `git` executable. Existing credential helpers, SSH setup, hooks, filters, and global configuration continue to work as expected.

### Shared engine

The Rust workspace provides repository inspection and mutation through a stable C ABI. A small CLI exercises the same data model without a graphical interface. The Windows client currently supports repository opening, history, working-copy state, patches, commits, and remote synchronization while its native experience is still being developed.

## Run the macOS app

Requirements:

- macOS 26 or newer
- Xcode 26 or newer with Swift 6.2
- A stable Rust toolchain
- Git available on `PATH`

Build the native core first, then launch the Swift package:

```sh
cargo build -p rift-ffi --release
swift run --package-path apps/macos RiftMac
```

To produce an ad-hoc signed `.app` bundle and DMG:

```sh
./scripts/package-macos.sh
```

Set `RIFT_CODESIGN_IDENTITY` to a Developer ID Application identity when making a distribution build. Notarization credentials are intentionally not stored in the repository.

## Build the shared workspace

```sh
cargo run -p rift-cli -- /path/to/a/repository
cargo test --workspace
cargo clippy --workspace --all-targets -- -D warnings
```

The CLI prints repository metadata, working-tree changes, and recent commits as JSON. See [the Windows notes](apps/windows/README.md) for its separate toolchain and build commands.

## Architecture

```text
                         installed Git
                              │
                     rift-core · Rust
                repository model + workflows
                              │
                       rift-ffi · C ABI
                   ┌──────────┴──────────┐
                   │                     │
          SwiftUI + AppKit          WinUI 3 + .NET
              macOS 26            Windows preview
```

- [`crates/rift-core`](crates/rift-core) — Git domain models and operations
- [`crates/rift-ffi`](crates/rift-ffi) — JSON-based native boundary and C header
- [`crates/rift-cli`](crates/rift-cli) — development and inspection harness
- [`apps/macos`](apps/macos) — current SwiftUI/AppKit product
- [`apps/windows`](apps/windows) — early WinUI client
- [`scripts`](scripts) — platform packaging scripts
- [`docs`](docs) — product direction and GitHub Pages site

Sharing the engine keeps operation semantics consistent. Each interface remains platform-native instead of sharing pixels or forcing a web UI onto the desktop.

## Nightly releases and in-app updates

Pushes to `master` refresh one rolling `nightly` prerelease instead of creating
an unlimited release history. It contains a universal macOS DMG, Windows
x64/arm64 archives, and a signed Sparkle appcast. Windows archives are manual
downloads for now; the Windows client does not claim self-update support.

Rift for macOS uses Sparkle 2.9.4. It checks the HTTPS feed daily and provides
**Rift > Check for Updates…**. Sparkle downloads the selected update, verifies
its Ed25519 signature, replaces the installed app, and relaunches it. Published
builds currently use ad-hoc code signing and require these Actions secrets:

- `SPARKLE_PUBLIC_ED_KEY`: public key printed by Sparkle `generate_keys`
- `SPARKLE_PRIVATE_ED_KEY`: exported Ed25519 private key contents

The release workflow has only `contents: write` permission. Never commit private
keys. Because the app is not Developer ID signed or notarized, macOS shows a
Gatekeeper warning on first launch; users must explicitly choose **Open** from
Finder's context menu. A future Developer ID release can remove this limitation.

## Roadmap

- Stabilize and polish the macOS workspace for everyday repositories.
- Improve performance and resilience for large histories and long-running Git operations.
- Expand keyboard navigation, accessibility, and Git workflow ergonomics.
- Bring the Windows client toward macOS workflow parity using native WinUI.
- Evaluate faster read paths in the Rust core without changing Git-compatible mutation behavior.

Roadmap items describe direction, not release commitments.

## Contributing

Issues and focused pull requests are welcome. Before opening a change, run the Rust test and lint commands above. macOS interface changes should also build the Swift package on macOS 26; Windows changes should build the WinUI project on a supported Windows machine.

## License

Rift is licensed under MIT; see the workspace metadata and distribution for details.
