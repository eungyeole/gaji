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
    private static let tabsKey = "workspaceRepositoryTabs"
    private static let selectedPathKey = "workspaceSelectedRepository"
    private(set) var tabs: [RepositoryTab]
    var selectedTabID: RepositoryTab.ID

    init() {
        let savedPaths = UserDefaults.standard.stringArray(forKey: Self.tabsKey)
        let paths = savedPaths ?? []
        let restored = paths.compactMap { path -> RepositoryTab? in
            guard FileManager.default.fileExists(atPath: path) else { return nil }
            let repository = RepositoryStore(restoreLastRepository: false)
            repository.open(URL(fileURLWithPath: path))
            return repository.root == nil ? nil : RepositoryTab(repository: repository)
        }
        if restored.isEmpty {
            let first = RepositoryTab(repository: RepositoryStore(restoreLastRepository: savedPaths == nil))
            tabs = [first]
            selectedTabID = first.id
        } else {
            tabs = restored
            let selectedPath = UserDefaults.standard.string(forKey: Self.selectedPathKey)
            selectedTabID = restored.first {
                $0.repository.root?.standardizedFileURL.path() == selectedPath
            }?.id ?? restored[0].id
        }
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
            persistTabs()
            return
        }
        if selectedRepository.root == nil {
            selectedRepository.open(url)
            persistTabs()
            return
        }
        let repository = RepositoryStore(restoreLastRepository: false)
        repository.open(url)
        guard repository.root != nil else { return }
        let tab = RepositoryTab(repository: repository)
        tabs.append(tab)
        selectedTabID = tab.id
        persistTabs()
    }

    func select(_ id: RepositoryTab.ID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        selectedTabID = id
        persistTabs()
    }

    func close(_ id: RepositoryTab.ID) {
        guard tabs.count > 1, let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let wasSelected = selectedTabID == id
        tabs.remove(at: index)
        if wasSelected {
            selectedTabID = tabs[min(index, tabs.count - 1)].id
        }
        persistTabs()
    }

    func persistTabs() {
        var seen = Set<String>()
        let paths = tabs.compactMap { $0.repository.root?.standardizedFileURL.path() }
            .filter { seen.insert($0).inserted }
        UserDefaults.standard.set(paths, forKey: Self.tabsKey)
        if let selectedPath = selectedRepository.root?.standardizedFileURL.path() {
            UserDefaults.standard.set(selectedPath, forKey: Self.selectedPathKey)
        }
    }
}
