import AppKit
import Foundation
import Observation

struct RepositoryTab: Identifiable {
    let id = UUID()
    let repository: RepositoryStore
}

@MainActor
@Observable
final class WorkspaceStore {
    private(set) var tabs: [RepositoryTab]
    var selectedTabID: RepositoryTab.ID

    init() {
        let first = RepositoryTab(repository: RepositoryStore())
        tabs = [first]
        selectedTabID = first.id
    }

    var selectedRepository: RepositoryStore {
        tabs.first(where: { $0.id == selectedTabID })?.repository ?? tabs[0].repository
    }

    func newTab() {
        let tab = RepositoryTab(repository: RepositoryStore(restoreLastRepository: false))
        tabs.append(tab)
        selectedTabID = tab.id
    }

    func chooseRepository() {
        let panel = NSOpenPanel()
        panel.title = "Open a Git Repository"
        panel.prompt = "Open"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openRepository(url)
    }

    func openRepository(_ url: URL) {
        let path = url.standardizedFileURL.path()
        if let existing = tabs.first(where: { $0.repository.root?.standardizedFileURL.path() == path }) {
            selectedTabID = existing.id
            return
        }
        if selectedRepository.root == nil {
            selectedRepository.open(url)
            return
        }
        let repository = RepositoryStore(restoreLastRepository: false)
        repository.open(url)
        guard repository.root != nil else { return }
        let tab = RepositoryTab(repository: repository)
        tabs.append(tab)
        selectedTabID = tab.id
    }

    func select(_ id: RepositoryTab.ID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        selectedTabID = id
    }

    func close(_ id: RepositoryTab.ID) {
        guard tabs.count > 1, let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let wasSelected = selectedTabID == id
        tabs.remove(at: index)
        if wasSelected {
            selectedTabID = tabs[min(index, tabs.count - 1)].id
        }
    }
}
