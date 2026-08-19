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

## Run the first vertical slice

```sh
cargo run -p rift-cli -- /path/to/a/repository
cargo test --workspace
```

The CLI prints the repository root, current branch, working-tree changes, and
recent commits as JSON. It is a development harness for the same model the
native applications will consume.

## Project layout

- `crates/rift-core`: shared Git operations and domain models
- `crates/rift-cli`: executable development harness
- `apps/macos`: SwiftUI/AppKit application (next milestone)
- `apps/windows`: WinUI 3 application (next milestone)
- `docs`: product and architecture decisions
