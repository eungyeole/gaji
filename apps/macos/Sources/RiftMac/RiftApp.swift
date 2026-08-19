import SwiftUI

@main
struct RiftApp: App {
    @State private var workspace = WorkspaceStore()

    var body: some Scene {
        WindowGroup {
            WorkspaceView()
                .environment(workspace)
                .frame(minWidth: 1100, minHeight: 680)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("New Tab") { workspace.newTab() }
                    .keyboardShortcut("t")
                Divider()
                Button("New Repository…") { workspace.selectedRepository.createRepository() }
                    .keyboardShortcut("n")
                Button("Clone Repository…") { workspace.selectedRepository.showsClone = true }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Button("Open Repository…") { workspace.chooseRepository() }
                    .keyboardShortcut("o")
                Button("Refresh") { workspace.selectedRepository.refresh() }
                    .keyboardShortcut("r")
                    .disabled(workspace.selectedRepository.root == nil)
            }
        }
        .defaultSize(width: 1280, height: 800)
    }
}
