# Rift

Rift is a native-first Git client for macOS and Windows. The Git domain logic is
implemented once in Rust, while each platform gets an interface that feels at
home on that operating system.

## Architecture

```text
                 rift-core (Rust)
              repository/domain model
                         |
              stable native API boundary
                 /                 \
     macOS (SwiftUI/AppKit)   Windows (WinUI 3)
       Liquid Glass style      Fluent design
```

The initial core intentionally talks to the installed `git` executable. This
keeps behavior compatible with users' authentication, hooks, filters, and Git
configuration. We can move performance-sensitive read operations to `gitoxide`
later without changing the platform interfaces.

## Implemented workflows

- Open, initialize, and clone repositories
- Commit graph, history search, file diff, blame, tags, remotes, and worktrees
- File and hunk stage/unstage, discard, commit, and amend engine support
- Branch create/switch/rename/delete, merge, cherry-pick, revert, and reset
- Rebase plus validated interactive pick/reword/edit/squash/fixup/drop plans
- Fetch, pull, push, force-with-lease engine support, stash, and submodules
- Conflict detection, continue/abort, ours/theirs, and 3-way merge content
- Shared C ABI consumed directly by the SwiftUI and WinUI applications

## Build and verify

```sh
cargo run -p rift-cli -- /path/to/a/repository
cargo test --workspace
cargo clippy --workspace --all-targets -- -D warnings
```

The CLI prints the repository root, current branch, working-tree changes, and
recent commits as JSON. It is a development harness for the same model the
native applications will consume.

## Project layout

- `crates/rift-core`: shared Git operations and domain models
- `crates/rift-ffi`: static/dynamic C ABI for native applications
- `crates/rift-cli`: executable development harness
- `apps/macos`: macOS 26 SwiftUI/AppKit application with Liquid Glass
- `apps/windows`: .NET 10 and Windows App SDK 2.3 WinUI 3 application
- `scripts`: reproducible macOS and Windows release packaging
- `docs`: product and architecture decisions
