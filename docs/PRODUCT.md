# Product direction

## Principle

Rift shares behavior, not pixels. Git concepts and operations remain consistent
across platforms; navigation, materials, controls, menus, keyboard behavior, and
window management follow the host platform.

## First usable release

1. Open and remember local repositories.
2. Show branches, a commit graph, file status, and diffs.
3. Stage and unstage individual files or hunks.
4. Commit, fetch, pull, push, create branches, and switch branches.
5. Use Keychain on macOS and Credential Manager on Windows for secrets.

## macOS experience

- SwiftUI scene and navigation architecture with AppKit where tighter window,
  menu, text-editor, or drag-and-drop control is needed.
- System materials and platform-provided glass effects instead of custom-drawn
  imitations.
- Native toolbar, sidebar, inspector, context menus, command menus, keyboard
  shortcuts, accessibility, and state restoration.
- Graceful visual fallback on macOS versions that predate Liquid Glass APIs.

## Windows experience

- WinUI 3 with native title bar integration, NavigationView, command surfaces,
  system context menus, keyboard navigation, and Fluent materials.
- Windows Credential Manager and standard shell integration.
