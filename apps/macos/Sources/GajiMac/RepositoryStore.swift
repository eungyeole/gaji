import AppKit
import Foundation
import Observation

struct FileChange: Identifiable, Hashable {
    let id = UUID()
    let indexStatus: Character
    let worktreeStatus: Character
    let path: String

    var statusLabel: String {
        if indexStatus == "?" { return "U" }
        return String(indexStatus == " " ? worktreeStatus : indexStatus)
    }
}

struct Commit: Identifiable, Hashable {
    let id: String
    let author: String
    let authorEmail: String
    let date: Date?
    let subject: String
    let parents: [String]
    let references: [String]

    init(id: String, author: String, authorEmail: String = "", date: Date?, subject: String, parents: [String] = [], references: [String] = []) {
        self.id = id
        self.author = author
        self.authorEmail = authorEmail
        self.date = date
        self.subject = subject
        self.parents = parents
        self.references = references
    }
}

enum GitOperation: String {
    case cherryPick = "Cherry-pick"
    case rebase = "Rebase"
    case merge = "Merge"
    case revert = "Revert"
}

enum PullBehavior: String, CaseIterable {
    case rebase
    case merge
    case fastForwardOnly

    var title: String {
        switch self {
        case .rebase: "Rebase Local Commits"
        case .merge: "Merge if Needed"
        case .fastForwardOnly: "Fast-Forward Only"
        }
    }
}

@MainActor
@Observable
final class RepositoryStore {
    @ObservationIgnored private var fileLoadTask: Task<Void, Never>?
    @ObservationIgnored private var commitLoadTask: Task<Void, Never>?
    @ObservationIgnored private var operationTask: Task<Void, Never>?
    @ObservationIgnored private var workingFileCache: [String: LoadedFileDetails] = [:]
    @ObservationIgnored private var commitFileCache: [String: String] = [:]
    @ObservationIgnored private var stashFileCache: [String: String] = [:]
    private(set) var root: URL?
    private(set) var branch = ""
    private(set) var changes: [FileChange] = []
    private(set) var commits: [Commit] = []
    private(set) var branches: [String] = []
    private(set) var remoteBranches: [String] = []
    private(set) var remotes: [String] = []
    private(set) var githubRepository: String?
    private(set) var stashes: [CoreStash] = []
    private(set) var tags: [String] = []
    private(set) var operation: GitOperation?
    private(set) var conflicts: [String] = []
    var errorMessage: String?
    private(set) var busyMessage: String?
    var isBusy: Bool { busyMessage != nil }
    var pullBehavior: PullBehavior
    var selection: Commit.ID?
    var selectedCommitIDs: Set<Commit.ID> = []
    var selectedFile: String?
    var selectedFileCommit: String?
    var selectedFileDiff = ""
    var selectedHunks: [CoreDiffHunk] = []
    var selectedFileIsStaged = false
    var selectedFileIsLoading = false
    private(set) var selectedCommitFiles: [CoreCommitFileChange] = []
    private(set) var selectedCommitFilesLoading = false
    private(set) var selectedStash: CoreStash?
    private(set) var selectedStashFiles: [CoreCommitFileChange] = []
    private(set) var selectedStashFilesLoading = false
    var commitMessage = ""
    var commitAmend = false
    var commitSign = false
    var commitSignoff = false
    var newBranchName = ""
    var showsCreateBranch = false
    var pendingHardReset: Commit?
    var conflictFile: String?
    var conflictBase = ""
    var conflictOurs = ""
    var conflictTheirs = ""
    var conflictResult = ""
    var cloneURL = ""
    var cloneDestination = ""
    var showsClone = false
    var rebaseUpstream = ""
    var rebaseSteps: [CoreRebaseStep] = []
    var showsInteractiveRebase = false
    var showsAddRemote = false
    var newRemoteName = "origin"
    var newRemoteURL = ""
    var taggingCommit: Commit?
    var newTagName = ""
    var searchText = ""
    var blameFile: String?
    var blameLines: [CoreBlameLine] = []
    var fileHistory: [CoreHistoryEntry] = []
    private(set) var recentRepositories: [String] = []
    private(set) var worktrees: [CoreWorktree] = []
    private(set) var submodules: [CoreSubmodule] = []
    var showsAddWorktree = false
    var worktreeDestination = ""
    var worktreeBranch = ""
    var renamingBranch: String?
    var renamedBranch = ""
    var deletingBranch: String?
    var pendingDiscardFiles: [String]?

    var title: String { root?.lastPathComponent ?? "Gaji" }
    var unstagedChanges: [FileChange] {
        changes.filter { $0.worktreeStatus != " " || $0.indexStatus == "?" }
    }
    var stagedChanges: [FileChange] {
        changes.filter { $0.indexStatus != " " && $0.indexStatus != "?" }
    }
    var checkedOutWorktreeBranches: Set<String> {
        Set(worktrees.compactMap(\.branch))
    }

    init(restoreLastRepository: Bool = true) {
        pullBehavior = PullBehavior(rawValue: UserDefaults.standard.string(forKey: "pullBehavior") ?? "") ?? .rebase
        recentRepositories = UserDefaults.standard.stringArray(forKey: "recentRepositories") ?? []
        if restoreLastRepository,
           let path = UserDefaults.standard.string(forKey: "lastRepository"),
           FileManager.default.fileExists(atPath: path) {
            open(URL(fileURLWithPath: path))
        }
    }

    func chooseRepository() {
        let panel = NSOpenPanel()
        panel.title = "Open a Git Repository"
        panel.prompt = "Open"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        open(url)
    }

    func open(_ url: URL) {
        do {
            let snapshot = try CoreBridge.inspect(url.path())
            root = URL(fileURLWithPath: snapshot.root)
            workingFileCache.removeAll()
            commitFileCache.removeAll()
            stashFileCache.removeAll()
            UserDefaults.standard.set(snapshot.root, forKey: "lastRepository")
            recentRepositories.removeAll { $0 == snapshot.root }
            recentRepositories.insert(snapshot.root, at: 0)
            recentRepositories = Array(recentRepositories.prefix(10))
            UserDefaults.standard.set(recentRepositories, forKey: "recentRepositories")
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openRecent(_ path: String) {
        guard FileManager.default.fileExists(atPath: path) else {
            recentRepositories.removeAll { $0 == path }
            UserDefaults.standard.set(recentRepositories, forKey: "recentRepositories")
            return
        }
        open(URL(fileURLWithPath: path))
    }

    func chooseCloneDestination() {
        let panel = NSSavePanel()
        panel.title = "Clone Repository"
        panel.prompt = "Choose"
        panel.canCreateDirectories = true
        let suggested = cloneURL.split(separator: "/").last.map(String.init)?
            .replacingOccurrences(of: ".git", with: "") ?? "repository"
        panel.nameFieldStringValue = suggested
        guard panel.runModal() == .OK, let url = panel.url else { return }
        cloneDestination = url.path()
    }

    func cloneRepository() {
        let url = cloneURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty, !cloneDestination.isEmpty else { return }
        let destination = cloneDestination
        showsClone = false
        runCore([
            "action": "clone", "url": url, "destination": destination, "bare": false
        ]) { [weak self] in
            self?.open(URL(fileURLWithPath: destination))
        }
    }

    func createRepository() {
        let panel = NSSavePanel()
        panel.title = "Create Repository"
        panel.prompt = "Create"
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "new-repository"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        runCore([
            "action": "initialize", "path": url.path(), "defaultBranch": "main"
        ]) { [weak self] in self?.open(url) }
    }

    func refresh() {
        guard let root else { return }
        workingFileCache.removeAll()
        do {
            let snapshot = try CoreBridge.inspect(root.path())
            branch = snapshot.branch
            changes = snapshot.changes.map {
                FileChange(
                    indexStatus: $0.indexStatus.first ?? " ",
                    worktreeStatus: $0.worktreeStatus.first ?? " ",
                    path: $0.path
                )
            }
            let formatter = ISO8601DateFormatter()
            commits = try CoreBridge.graph(root.path()).map {
                Commit(
                    id: $0.id, author: $0.author, authorEmail: $0.authorEmail,
                    date: formatter.date(from: $0.authoredAt),
                    subject: $0.subject, parents: $0.parents, references: $0.references
                )
            }
            branches = try git(at: root, "branch", "--format=%(refname:short)")
                .split(separator: "\n").map(String.init)
            remoteBranches = try git(at: root, "for-each-ref", "--format=%(refname:short)", "refs/remotes")
                .split(separator: "\n")
                .map(String.init)
                .filter { !$0.hasSuffix("/HEAD") }
            remotes = try git(at: root, "remote").split(separator: "\n").map(String.init)
            let remote = remotes.contains("origin") ? "origin" : remotes.first
            githubRepository = remote
                .flatMap { try? git(at: root, "remote", "get-url", $0) }
                .flatMap(Self.githubRepository(from:))
            stashes = (try? CoreBridge.stashes(root.path())) ?? []
            tags = try git(at: root, "tag", "--list").split(separator: "\n").map(String.init)
            worktrees = (try? CoreBridge.worktrees(root.path())) ?? []
            submodules = (try? CoreBridge.submodules(root.path())) ?? []
            let state = try CoreBridge.operationState(root.path())
            operation = switch state.operation {
            case "cherryPick": .cherryPick
            case "rebase": .rebase
            case "merge": .merge
            case "revert": .revert
            default: nil
            }
            conflicts = state.conflicts
            if selectedFileCommit == nil, let selectedFile, !changes.contains(where: { $0.path == selectedFile }) {
                closeFileDetails()
            }
            let commitIDs = Set(commits.map(\.id))
            selectedCommitIDs.formIntersection(commitIDs)
            if let selection, !commitIDs.contains(selection) {
                self.selection = changes.isEmpty ? commits.first?.id : nil
            } else if selection == nil, changes.isEmpty {
                selection = commits.first?.id
            }
            if let selection { selectedCommitIDs.insert(selection) }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func cherryPick(_ commit: Commit) {
        runCore(["action": "cherryPick", "path": rootPath, "revision": commit.id])
    }

    func cherryPick(_ commits: [Commit]) {
        let revisions = commitsInReplayOrder(commits).map(\.id)
        guard !revisions.isEmpty else { return }
        runCore(["action": "cherryPickMany", "path": rootPath, "revisions": revisions])
    }

    func updateCommitSelection(_ ids: Set<Commit.ID>, ordered visibleIDs: [Commit.ID]) {
        let added = ids.subtracting(selectedCommitIDs)
        selectedCommitIDs = ids
        if ids.isEmpty {
            selection = nil
        } else if added.count == 1 {
            selection = added.first
        } else if selection == nil || !ids.contains(selection!) {
            selection = visibleIDs.first(where: ids.contains)
        }
    }

    func clearCommitSelection() {
        selectedCommitIDs = []
        selection = nil
    }

    func select(_ change: FileChange, staged: Bool? = nil) {
        guard let root else { return }
        selectedStash = nil
        selectedStashFiles = []
        fileLoadTask?.cancel()
        selectedFile = change.path
        selectedFileCommit = nil
        clearCommitSelection()
        let inspectStaged = staged ?? (change.indexStatus != " " && change.indexStatus != "?")
        selectedFileIsStaged = inspectStaged
        let rootPath = root.path()
        let file = change.path
        let cacheKey = "\(rootPath):\(inspectStaged):\(file)"
        if let details = workingFileCache[cacheKey] {
            selectedFileDiff = details.diff
            selectedHunks = details.hunks
            selectedFileIsLoading = false
            return
        }
        selectedFileIsLoading = true
        selectedFileDiff = ""
        selectedHunks = []
        fileLoadTask = Task { [weak self] in
            let details = await Task.detached(priority: .userInitiated) {
                Self.loadFileDetails(rootPath: rootPath, file: file, staged: inspectStaged)
            }.value
            guard !Task.isCancelled,
                  let self,
                  self.selectedFile == file,
                  self.selectedFileIsStaged == inspectStaged else { return }
            self.workingFileCache[cacheKey] = details
            self.selectedFileDiff = details.diff
            self.selectedHunks = details.hunks
            self.selectedFileIsLoading = false
        }
    }

    func selectCommit(_ id: String?) {
        commitLoadTask?.cancel()
        selectedCommitFiles = []
        selectedCommitFilesLoading = false
        guard let root, let id else { return }
        selectedStash = nil
        selectedStashFiles = []
        closeFileDetails()
        selectedCommitFilesLoading = true
        let rootPath = root.path()
        commitLoadTask = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                Result { try CoreBridge.commitFiles(rootPath, commit: id) }
            }.value
            guard !Task.isCancelled, let self, self.selection == id else { return }
            switch result {
            case let .success(files): self.selectedCommitFiles = files
            case let .failure(error): self.errorMessage = error.localizedDescription
            }
            self.selectedCommitFilesLoading = false
        }
    }

    func selectCommitFile(_ change: CoreCommitFileChange) {
        guard let root, let commit = selection else { return }
        fileLoadTask?.cancel()
        selectedFile = change.path
        selectedFileCommit = commit
        let rootPath = root.path()
        let cacheKey = "\(rootPath):\(commit):\(change.path)"
        if let diff = commitFileCache[cacheKey] {
            selectedFileDiff = diff
            selectedHunks = []
            selectedFileIsLoading = false
            return
        }
        selectedFileDiff = ""
        selectedHunks = []
        selectedFileIsLoading = true
        fileLoadTask = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                Result { try CoreBridge.commitFileDiff(rootPath, commit: commit, file: change.path) }
            }.value
            guard !Task.isCancelled,
                  let self,
                  self.selectedFile == change.path,
                  self.selectedFileCommit == commit else { return }
            switch result {
            case let .success(diff):
                self.commitFileCache[cacheKey] = diff
                self.selectedFileDiff = diff
            case let .failure(error): self.errorMessage = error.localizedDescription
            }
            self.selectedFileIsLoading = false
        }
    }

    func closeFileDetails() {
        fileLoadTask?.cancel()
        selectedFile = nil
        selectedFileCommit = nil
        selectedFileDiff = ""
        selectedHunks = []
        selectedFileIsLoading = false
    }

    func selectStash(_ stash: CoreStash) {
        guard let root else { return }
        commitLoadTask?.cancel()
        clearCommitSelection()
        selectedCommitFiles = []
        closeFileDetails()
        selectedStash = stash
        selectedStashFiles = []
        selectedStashFilesLoading = true
        let rootPath = root.path()
        commitLoadTask = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                Result { try CoreBridge.stashFiles(rootPath, index: stash.index) }
            }.value
            guard !Task.isCancelled, let self, self.selectedStash?.reference == stash.reference else { return }
            switch result {
            case let .success(files): self.selectedStashFiles = files
            case let .failure(error): self.errorMessage = error.localizedDescription
            }
            self.selectedStashFilesLoading = false
        }
    }

    func selectStashFile(_ change: CoreCommitFileChange) {
        guard let root, let stash = selectedStash else { return }
        fileLoadTask?.cancel()
        selectedFile = change.path
        selectedFileCommit = stash.reference
        selectedHunks = []
        let rootPath = root.path()
        let cacheKey = "\(rootPath):\(stash.reference):\(change.path)"
        if let diff = stashFileCache[cacheKey] {
            selectedFileDiff = diff
            selectedFileIsLoading = false
            return
        }
        selectedFileDiff = ""
        selectedFileIsLoading = true
        fileLoadTask = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                Result { try CoreBridge.stashFileDiff(rootPath, index: stash.index, file: change.path) }
            }.value
            guard !Task.isCancelled,
                  let self,
                  self.selectedStash?.reference == stash.reference,
                  self.selectedFile == change.path else { return }
            switch result {
            case let .success(diff):
                self.stashFileCache[cacheKey] = diff
                self.selectedFileDiff = diff
            case let .failure(error): self.errorMessage = error.localizedDescription
            }
            self.selectedFileIsLoading = false
        }
    }

    func closeStashDetails() {
        commitLoadTask?.cancel()
        selectedStash = nil
        selectedStashFiles = []
        selectedStashFilesLoading = false
        closeFileDetails()
    }

    func apply(_ hunk: CoreDiffHunk) {
        runCore([
            "action": "applyPatch", "path": rootPath, "patch": hunk.patch,
            "staged": true, "reverse": selectedFileIsStaged
        ]) { [weak self] in
            guard let self, let file = self.selectedFile,
                  let change = self.changes.first(where: { $0.path == file }) else { return }
            self.select(change)
        }
    }

    func openBlame(_ file: String) {
        do {
            blameLines = try CoreBridge.blame(rootPath, file: file)
            fileHistory = try CoreBridge.fileHistory(rootPath, file: file)
            blameFile = file
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stage(_ file: String) {
        runCore(["action": "stage", "path": rootPath, "files": [file]]) { [weak self] in
            guard let self, self.selectedFile == file,
                  let change = self.changes.first(where: { $0.path == file }) else { return }
            self.select(change, staged: true)
        }
    }

    func stageAll() {
        let files = Array(Set(unstagedChanges.map(\.path))).sorted()
        guard !files.isEmpty else { return }
        runCore(["action": "stage", "path": rootPath, "files": files])
    }

    func unstage(_ file: String) {
        runCore(["action": "unstage", "path": rootPath, "files": [file]]) { [weak self] in
            guard let self, self.selectedFile == file,
                  let change = self.changes.first(where: { $0.path == file }) else { return }
            self.select(change, staged: false)
        }
    }

    func unstageAll() {
        let files = Array(Set(stagedChanges.map(\.path))).sorted()
        guard !files.isEmpty else { return }
        runCore(["action": "unstage", "path": rootPath, "files": files])
    }

    func discard(_ file: String) {
        runCore(["action": "discard", "path": rootPath, "files": [file]])
    }

    func requestDiscard(_ files: [String]) {
        let tracked = Array(Set(files.filter { file in
            changes.contains { $0.path == file && ($0.worktreeStatus != " " || $0.indexStatus == "?") }
        })).sorted()
        guard !tracked.isEmpty else { return }
        pendingDiscardFiles = tracked
    }

    func confirmDiscard() {
        guard let files = pendingDiscardFiles, !files.isEmpty else { return }
        pendingDiscardFiles = nil
        runCore(["action": "discard", "path": rootPath, "files": files])
    }

    func createCommit(amend: Bool? = nil) {
        let message = commitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        runCore([
            "action": "commit", "path": rootPath, "message": message,
            "amend": amend ?? commitAmend, "sign": commitSign,
            "signoff": commitSignoff, "allowEmpty": false
        ]) { [weak self] in self?.commitMessage = "" }
    }

    func switchBranch(_ name: String) {
        prepareForRepositoryTransition()
        runCore(["action": "switchBranch", "path": rootPath, "branch": name])
    }

    func switchRemoteBranch(_ name: String) {
        let localName = name.split(separator: "/", maxSplits: 1).last.map(String.init) ?? name
        if branches.contains(localName) {
            switchBranch(localName)
        } else {
            prepareForRepositoryTransition()
            runCore([
                "action": "createBranch", "path": rootPath, "name": localName,
                "start": name, "switch": true
            ])
        }
    }
    func merge(_ name: String) {
        runCore(["action": "merge", "path": rootPath, "revision": name, "noFastForward": false])
    }
    func rebase(onto name: String) {
        runCore(["action": "rebase", "path": rootPath, "upstream": name])
    }

    func prepareInteractiveRebase(onto name: String) {
        do {
            rebaseUpstream = name
            rebaseSteps = try CoreBridge.rebasePlan(rootPath, upstream: name)
            showsInteractiveRebase = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func prepareSquash(_ selected: [Commit]) {
        let commits = commitsInReplayOrder(selected)
        guard commits.count > 1, let oldest = commits.first else { return }
        do {
            let upstream = "\(oldest.id)^"
            let plan = try CoreBridge.rebasePlan(rootPath, upstream: upstream)
            guard Set(plan.map(\.commit)) == Set(commits.map(\.id)) else {
                throw CoreError.message("Squash requires contiguous commits on the current branch.")
            }
            rebaseUpstream = upstream
            rebaseSteps = plan.enumerated().map { index, step in
                var step = step
                step.action = index == 0 ? "pick" : "squash"
                return step
            }
            showsInteractiveRebase = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func moveRebaseStep(_ index: Int, by offset: Int) {
        let destination = index + offset
        guard rebaseSteps.indices.contains(index), rebaseSteps.indices.contains(destination) else { return }
        rebaseSteps.swapAt(index, destination)
    }

    func startInteractiveRebase() {
        let steps = rebaseSteps.map {
            ["action": $0.action, "commit": $0.commit, "subject": $0.subject]
        }
        showsInteractiveRebase = false
        runCore([
            "action": "interactiveRebase", "path": rootPath,
            "upstream": rebaseUpstream, "steps": steps
        ])
    }

    func addRemote() {
        let name = newRemoteName.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = newRemoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !url.isEmpty else { return }
        showsAddRemote = false
        runCore(["action": "addRemote", "path": rootPath, "name": name, "url": url])
    }

    func removeRemote(_ name: String) {
        runCore(["action": "removeRemote", "path": rootPath, "name": name])
    }

    func createTag() {
        guard let commit = taggingCommit else { return }
        let name = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        taggingCommit = nil
        runCore([
            "action": "createTag", "path": rootPath, "name": name,
            "target": commit.id
        ])
        newTagName = ""
    }

    func deleteTag(_ name: String) {
        runCore(["action": "deleteTag", "path": rootPath, "name": name])
    }

    func pushTag(_ name: String) {
        guard let remote = remotes.first else { return }
        runCore(["action": "pushTag", "path": rootPath, "remote": remote, "name": name])
    }

    func chooseWorktreeDestination() {
        let panel = NSSavePanel()
        panel.title = "Add Worktree"
        panel.prompt = "Choose"
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = worktreeBranch.isEmpty ? "worktree" : worktreeBranch
        guard panel.runModal() == .OK, let url = panel.url else { return }
        worktreeDestination = url.path()
    }

    func addWorktree() {
        guard !worktreeDestination.isEmpty, !worktreeBranch.isEmpty else { return }
        showsAddWorktree = false
        runCore([
            "action": "addWorktree", "path": rootPath,
            "destination": worktreeDestination, "branch": worktreeBranch
        ])
    }

    func removeWorktree(_ path: String) {
        runCore([
            "action": "removeWorktree", "path": rootPath,
            "destination": path, "force": false
        ])
    }

    func updateSubmodules() {
        runCore(["action": "updateSubmodules", "path": rootPath, "initialize": true])
    }

    func createBranch() {
        let name = newBranchName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        runCore([
            "action": "createBranch", "path": rootPath, "name": name,
            "start": "HEAD", "switch": true
        ]) { [weak self] in
            self?.newBranchName = ""
            self?.showsCreateBranch = false
        }
    }

    func beginRenameBranch(_ name: String) {
        renamingBranch = name
        renamedBranch = name
    }

    func renameBranch() {
        guard let old = renamingBranch else { return }
        let new = renamedBranch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !new.isEmpty else { return }
        renamingBranch = nil
        runCore(["action": "renameBranch", "path": rootPath, "old": old, "new": new])
    }

    func deleteBranch() {
        guard let name = deletingBranch else { return }
        deletingBranch = nil
        runCore(["action": "deleteBranch", "path": rootPath, "name": name, "force": false])
    }

    func fetch() {
        guard let remote = remotes.first else { return }
        fetch(remote)
    }
    func fetch(_ remote: String) {
        runCore(["action": "fetch", "path": rootPath, "remote": remote, "prune": true])
    }
    func pull() { pull(pullBehavior) }
    func pull(_ behavior: PullBehavior) {
        pullBehavior = behavior
        UserDefaults.standard.set(behavior.rawValue, forKey: "pullBehavior")
        runCore([
            "action": "pull", "path": rootPath,
            "rebase": behavior == .rebase,
            "fastForwardOnly": behavior == .fastForwardOnly
        ])
    }
    func push() {
        guard let remote = remotes.first else { return }
        runCore([
            "action": "push", "path": rootPath, "remote": remote, "branch": branch,
            "setUpstream": false, "forceWithLease": false
        ])
    }
    func stash() {
        runCore([
            "action": "stashPush", "path": rootPath, "message": "Gaji stash", "includeUntracked": true
        ])
    }
    func popStash() {
        closeStashDetails()
        runCore(["action": "stashApply", "path": rootPath, "index": 0, "pop": true])
    }
    func applyStash(_ index: Int, pop: Bool) {
        closeStashDetails()
        runCore(["action": "stashApply", "path": rootPath, "index": index, "pop": pop])
    }
    func dropStash(_ index: Int) {
        closeStashDetails()
        runCore(["action": "stashDrop", "path": rootPath, "index": index])
    }
    func revert(_ commit: Commit) {
        runCore(["action": "revert", "path": rootPath, "target": commit.id])
    }

    func reset(to commit: Commit, mode: String) {
        let modeName = switch mode {
        case "--soft": "soft"
        case "--hard": "hard"
        default: "mixed"
        }
        runCore(["action": "reset", "path": rootPath, "target": commit.id, "mode": modeName])
        pendingHardReset = nil
    }

    func continueOperation() {
        guard let operation else { return }
        _ = operation
        runCore(["action": "continue", "path": rootPath])
    }

    func abortOperation() {
        guard let operation else { return }
        _ = operation
        runCore(["action": "abort", "path": rootPath])
    }

    func resolve(_ file: String, using side: String?) {
        let sideName = side == "--ours" ? "ours" : side == "--theirs" ? "theirs" : nil
        var request: [String: Any] = ["action": "resolve", "path": rootPath, "file": file]
        if let sideName { request["side"] = sideName }
        runCore(request)
    }

    func openConflictEditor(_ file: String) {
        guard let root else { return }
        conflictFile = file
        conflictBase = (try? git(at: root, "show", ":1:\(file)")) ?? ""
        conflictOurs = (try? git(at: root, "show", ":2:\(file)")) ?? ""
        conflictTheirs = (try? git(at: root, "show", ":3:\(file)")) ?? ""
        conflictResult = (try? String(contentsOf: root.appending(path: file), encoding: .utf8)) ?? ""
    }

    func saveConflictResult() {
        guard let root, let conflictFile else { return }
        do {
            try conflictResult.write(to: root.appending(path: conflictFile), atomically: true, encoding: .utf8)
            self.conflictFile = nil
            runCore(["action": "resolve", "path": root.path(), "file": conflictFile])
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var rootPath: String { root?.path() ?? "" }

    private func prepareForRepositoryTransition() {
        fileLoadTask?.cancel()
        commitLoadTask?.cancel()
        clearCommitSelection()
        selectedCommitFiles = []
        selectedCommitFilesLoading = false
        closeStashDetails()
    }

    private func commitsInReplayOrder(_ selected: [Commit]) -> [Commit] {
        let ids = Set(selected.map(\.id))
        return Array(commits.filter { ids.contains($0.id) }.reversed())
    }

    private nonisolated static func loadFileDetails(
        rootPath: String, file: String, staged: Bool
    ) -> LoadedFileDetails {
        guard let details = try? CoreBridge.fileDiff(rootPath, file: file, staged: staged) else {
            return LoadedFileDetails(diff: "", hunks: [])
        }
        return LoadedFileDetails(diff: details.patch, hunks: details.hunks)
    }

    private func runCore(_ request: [String: Any], onSuccess: (() -> Void)? = nil) {
        guard !isBusy else { return }
        let json: String
        do {
            let data = try JSONSerialization.data(withJSONObject: request)
            guard let encoded = String(data: data, encoding: .utf8) else {
                throw CoreError.message("Could not encode native request")
            }
            json = encoded
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        busyMessage = operationMessage(request)
        errorMessage = nil
        operationTask = Task { [weak self] in
            let operationError = await Task.detached(priority: .userInitiated) {
                do {
                    try CoreBridge.execute(json: json)
                    return nil as String?
                } catch {
                    return error.localizedDescription
                }
            }.value
            guard let self else { return }
            self.refresh()
            self.busyMessage = nil
            if operationError == nil { onSuccess?() }
            if self.conflicts.isEmpty { self.errorMessage = operationError }
        }
    }

    private func operationMessage(_ request: [String: Any]) -> String {
        let action = request["action"] as? String ?? "git"
        switch action {
        case "clone": return "Cloning repository…"
        case "initialize": return "Creating repository…"
        case "switchBranch": return "Switching to \(request["branch"] as? String ?? "branch")…"
        case "createBranch": return "Creating branch…"
        case "fetch": return "Fetching from \(request["remote"] as? String ?? "remote")…"
        case "pull": return "Pulling changes…"
        case "push", "pushTag": return "Pushing changes…"
        case "merge": return "Merging branches…"
        case "rebase", "interactiveRebase": return "Rebasing commits…"
        case "cherryPick", "cherryPickMany": return "Cherry-picking commits…"
        case "revert": return "Reverting commit…"
        case "commit": return "Creating commit…"
        case "stage": return "Staging changes…"
        case "unstage": return "Unstaging changes…"
        case "discard": return "Discarding changes…"
        case "stashPush", "stashApply", "stashDrop": return "Updating stash…"
        case "addWorktree", "removeWorktree": return "Updating worktrees…"
        case "updateSubmodules": return "Updating submodules…"
        default: return "Running Git operation…"
        }
    }

    private func git(at root: URL, _ arguments: String...) throws -> String {
        try git(at: root, arguments)
    }

    private func git(at root: URL, _ arguments: [String]) throws -> String {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", root.path()] + arguments
        process.standardOutput = stdout
        process.standardError = stderr
        process.environment = ProcessInfo.processInfo.environment.merging([
            "GIT_EDITOR": "true",
            "GIT_SEQUENCE_EDITOR": "true"
        ]) { _, new in new }
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = stderr.fileHandleForReading.readDataToEndOfFile()
            let message = String(decoding: data, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw GitError.failed(message.isEmpty ? "Git command failed" : message)
        }
        return String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }

    private nonisolated static func githubRepository(from remote: String) -> String? {
        let normalized = remote.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "git@github.com:", with: "https://github.com/")
        guard let url = URL(string: normalized), url.host?.lowercased() == "github.com" else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return nil }
        return "\(parts[0])/\(parts[1].replacingOccurrences(of: ".git", with: ""))"
    }

}

private struct LoadedFileDetails: Sendable {
    let diff: String
    let hunks: [CoreDiffHunk]
}

enum GitError: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .failed(let message): message
        }
    }
}
