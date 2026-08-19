import SwiftUI

@main
struct RiftApp: App {
    @State private var repository = RepositoryStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(repository)
                .frame(minWidth: 980, minHeight: 640)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open Repository…") { repository.chooseRepository() }
                    .keyboardShortcut("o")
                Button("Refresh") { repository.refresh() }
                    .keyboardShortcut("r")
                    .disabled(repository.root == nil)
            }
        }
        .defaultSize(width: 1280, height: 800)
    }
}
