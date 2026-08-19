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
    let date: Date?
    let subject: String
    let parents: [String]
    let references: [String]

    init(id: String, author: String, date: Date?, subject: String, parents: [String] = [], references: [String] = []) {
        self.id = id
        self.author = author
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

@MainActor
@Observable
final class RepositoryStore {
    private(set) var root: URL?
    private(set) var branch = ""
    private(set) var changes: [FileChange] = []
    private(set) var commits: [Commit] = []
    private(set) var branches: [String] = []
    private(set) var remoteBranches: [String] = []
    private(set) var remotes: [String] = []
    private(set) var stashes: [CoreStash] = []
    private(set) var tags: [String] = []
    private(set) var operation: GitOperation?
    private(set) var conflicts: [String] = []
    var errorMessage: String?
    var selection: Commit.ID?
    var selectedFile: String?
    var selectedFileDiff = ""
    var selectedCommitDiff = ""
    var selectedHunks: [CoreDiffHunk] = []
    var selectedFileIsStaged = false
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

    var title: String { root?.lastPathComponent ?? "Rift" }
    var unstagedChanges: [FileChange] {
        changes.filter { $0.worktreeStatus != " " || $0.indexStatus == "?" }
    }
    var stagedChanges: [FileChange] {
        changes.filter { $0.indexStatus != " " && $0.indexStatus != "?" }
    }
    var checkedOutWorktreeBranches: Set<String> {
        Set(worktrees.compactMap(\.branch))
    }

    init() {
        recentRepositories = UserDefaults.standard.stringArray(forKey: "recentRepositories") ?? []
        if let path = UserDefaults.standard.string(forKey: "lastRepository"),
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
        do {
            try CoreBridge.execute([
                "action": "clone", "url": url, "destination": cloneDestination, "bare": false
            ])
            showsClone = false
            open(URL(fileURLWithPath: cloneDestination))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createRepository() {
        let panel = NSSavePanel()
        panel.title = "Create Repository"
        panel.prompt = "Create"
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "new-repository"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try CoreBridge.execute([
                "action": "initialize", "path": url.path(), "defaultBranch": "main"
            ])
            open(url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refresh() {
        guard let root else { return }
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
                    id: $0.id, author: $0.author, date: formatter.date(from: $0.authoredAt),
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
            if let selectedFile, !changes.contains(where: { $0.path == selectedFile }) {
                self.selectedFile = nil
                selectedFileDiff = ""
                selectedHunks = []
            }
            if let selection, !commits.contains(where: { $0.id == selection }) {
                self.selection = changes.isEmpty ? commits.first?.id : nil
            } else if selection == nil, changes.isEmpty {
                selection = commits.first?.id
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func cherryPick(_ commit: Commit) {
        runCore(["action": "cherryPick", "path": rootPath, "revision": commit.id])
    }

    func select(_ commit: Commit) {
        guard let root else { return }
        selectedFile = nil
        selection = commit.id
        selectedCommitDiff = (try? git(
            at: root, "show", "--format=fuller", "--stat", "--patch", "--no-ext-diff", commit.id
        )) ?? ""
    }

    func select(_ change: FileChange, staged: Bool? = nil) {
        guard let root else { return }
        selectedFile = change.path
        selection = nil
        let inspectStaged = staged ?? (change.indexStatus != " " && change.indexStatus != "?")
        selectedFileIsStaged = inspectStaged
        selectedFileDiff = (try? git(
            at: root, "diff", inspectStaged ? "--cached" : "--no-ext-diff", "--", change.path
        )) ?? ""
        selectedHunks = (try? CoreBridge.hunks(root.path(), file: change.path, staged: inspectStaged)) ?? []
    }

    func apply(_ hunk: CoreDiffHunk) {
        runCore([
            "action": "applyPatch", "path": rootPath, "patch": hunk.patch,
            "staged": true, "reverse": selectedFileIsStaged
        ])
        if let file = selectedFile, let change = changes.first(where: { $0.path == file }) {
            select(change)
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
        runCore(["action": "stage", "path": rootPath, "files": [file]])
        if selectedFile == file, let change = changes.first(where: { $0.path == file }) {
            select(change, staged: true)
        }
    }

    func stageAll() {
        let files = Array(Set(unstagedChanges.map(\.path))).sorted()
        guard !files.isEmpty else { return }
        runCore(["action": "stage", "path": rootPath, "files": files])
    }

    func unstage(_ file: String) {
        runCore(["action": "unstage", "path": rootPath, "files": [file]])
        if selectedFile == file, let change = changes.first(where: { $0.path == file }) {
            select(change, staged: false)
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
        ])
        if errorMessage == nil { commitMessage = "" }
    }

    func switchBranch(_ name: String) {
        runCore(["action": "switchBranch", "path": rootPath, "branch": name])
    }

    func switchRemoteBranch(_ name: String) {
        let localName = name.split(separator: "/", maxSplits: 1).last.map(String.init) ?? name
        if branches.contains(localName) {
            switchBranch(localName)
        } else {
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
        runCore(["action": "createBranch", "path": rootPath, "name": name, "start": "HEAD", "switch": true])
        if errorMessage == nil {
            newBranchName = ""
            showsCreateBranch = false
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
    func pull() { runCore(["action": "pull", "path": rootPath, "rebase": true]) }
    func push() {
        guard let remote = remotes.first else { return }
        runCore([
            "action": "push", "path": rootPath, "remote": remote, "branch": branch,
            "setUpstream": false, "forceWithLease": false
        ])
    }
    func stash() {
        runCore([
            "action": "stashPush", "path": rootPath, "message": "Rift stash", "includeUntracked": true
        ])
    }
    func popStash() {
        runCore(["action": "stashApply", "path": rootPath, "index": 0, "pop": true])
    }
    func applyStash(_ index: Int, pop: Bool) {
        runCore(["action": "stashApply", "path": rootPath, "index": index, "pop": pop])
    }
    func dropStash(_ index: Int) {
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

    private func runCore(_ request: [String: Any]) {
        var operationError: String?
        do {
            try CoreBridge.execute(request)
        } catch {
            operationError = error.localizedDescription
        }
        refresh()
        if conflicts.isEmpty { errorMessage = operationError }
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

}

enum GitError: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .failed(let message): message
        }
    }
}
