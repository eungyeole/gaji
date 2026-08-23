<div align="center">
  <img src="docs/public/gaji-mark.svg" width="72" height="72" alt="Gaji">
  <h1>Gaji</h1>
  <p><strong>Native throughout.</strong></p>
  <p>Liquid Glass. Small footprint. Native speed.</p>
  <p><a href="https://github.com/eungyeole/gaji/releases/download/nightly/Gaji-macOS.dmg">Download for macOS</a> · <a href="https://gaji.eungyeole.com/">Website</a> · <a href="https://github.com/eungyeole/gaji/releases">Releases</a></p>
</div>

<br>

![Gaji showing branches, commit history, and changed files](docs/public/gaji-workspace.png)

## Less app. More Mac.

Gaji is a focused Git client built with SwiftUI, AppKit, and a Rust core. It uses native macOS controls and materials instead of shipping a browser runtime, so it feels at home, starts quickly, and stays compact.

- **Liquid Glass** — system materials, controls, menus, and window behavior.
- **Small footprint** — a native interface with no bundled browser.
- **Native speed** — responsive system UI backed by a fast shared Git engine.

## A complete Git workspace

History, branches, worktrees, stashes, changes, and diffs live in one window. Gaji supports everyday Git work including staging individual files or hunks, commits, fetch, pull, push, merge, rebase, cherry-pick, conflict resolution, remotes, tags, worktrees, and submodules.

Repository tabs return after relaunch. Commit and stash inspection share the same file and diff experience. Existing Git credentials, SSH configuration, hooks, filters, and global settings continue to work through the installed `git` executable.

> Gaji currently focuses on macOS 26. The native Windows client is planned for a later release.

## Build

Requires macOS 26+, Xcode 26 with Swift 6.2, stable Rust, and Git on `PATH`.

```sh
cargo build -p gaji-ffi --release
swift run --package-path apps/macos GajiMac
```

Create an ad-hoc signed app bundle and DMG:

```sh
./scripts/package-macos.sh
```

The packaged preview is not notarized. On first launch, Control-click Gaji in Finder and choose **Open**.

## Project

```text
apps/macos        SwiftUI + AppKit app
apps/windows      WinUI preview
crates/gaji-core  Git models and workflows
crates/gaji-ffi   Native C boundary
crates/gaji-cli   Development CLI
docs              Product site
```

The Rust engine owns Git behavior while each platform keeps its own native interface. See [macOS notes](apps/macos/README.md), [Windows status](apps/windows/README.md), or [product direction](docs/PRODUCT.md) for more detail.

<details>
<summary>Development checks</summary>

```sh
cargo test --workspace
cargo clippy --workspace --all-targets -- -D warnings
```

Running the Nightly release workflow manually creates a versioned prerelease and refreshes the rolling nightly feed. Adding the Sparkle signing secrets enables the signed update feed and **Gaji → Check for Updates…** flow; DMG releases remain available without them.

</details>

## Contributing

Issues and focused pull requests are welcome. Gaji is available under the MIT license.
