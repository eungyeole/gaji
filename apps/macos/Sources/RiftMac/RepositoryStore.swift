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
    private(set) var remotes: [String] = []
    private(set) var stashes: [String] = []
    private(set) var operation: GitOperation?
    private(set) var conflicts: [String] = []
    var errorMessage: String?
    var selection: Commit.ID?
    var selectedFile: String?
    var selectedFileDiff = ""
    var commitMessage = ""
    var newBranchName = ""
    var showsCreateBranch = false

    var title: String { root?.lastPathComponent ?? "Rift" }

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
            let rootPath = try git(at: url, "rev-parse", "--show-toplevel")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            root = URL(fileURLWithPath: rootPath)
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refresh() {
        guard let root else { return }
        do {
            branch = try git(at: root, "branch", "--show-current")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            changes = parseStatus(try git(at: root, "status", "--porcelain=v1"))
            commits = parseLog(gitAllowingEmptyHistory(at: root))
            branches = try git(at: root, "branch", "--format=%(refname:short)")
                .split(separator: "\n").map(String.init)
            remotes = try git(at: root, "remote").split(separator: "\n").map(String.init)
            stashes = try git(at: root, "stash", "list", "--format=%gd %s")
                .split(separator: "\n").map(String.init)
            operation = detectOperation(at: root)
            conflicts = try git(at: root, "diff", "--name-only", "--diff-filter=U")
                .split(separator: "\n").map(String.init)
            if !commits.contains(where: { $0.id == selection }) {
                selection = commits.first?.id
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func cherryPick(_ commit: Commit) {
        runOperation("cherry-pick", commit.id)
    }

    func select(_ change: FileChange) {
        guard let root else { return }
        selectedFile = change.path
        let staged = change.indexStatus != " " && change.indexStatus != "?"
        selectedFileDiff = (try? git(
            at: root, "diff", staged ? "--cached" : "--no-ext-diff", "--", change.path
        )) ?? ""
    }

    func stage(_ file: String) {
        runOperation("add", "--", file)
    }

    func unstage(_ file: String) {
        runOperation("restore", "--staged", "--", file)
    }

    func discard(_ file: String) {
        runOperation("restore", "--worktree", "--", file)
    }

    func createCommit(amend: Bool = false) {
        let message = commitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        if amend {
            runOperation("commit", "--amend", "-m", message)
        } else {
            runOperation("commit", "-m", message)
        }
        if errorMessage == nil { commitMessage = "" }
    }

    func switchBranch(_ name: String) { runOperation("switch", name) }

    func createBranch() {
        let name = newBranchName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        runOperation("switch", "-c", name)
        if errorMessage == nil {
            newBranchName = ""
            showsCreateBranch = false
        }
    }

    func fetch() { runOperation("fetch", "--all", "--prune") }
    func pull() { runOperation("pull", "--rebase") }
    func push() { runOperation("push") }
    func stash() { runOperation("stash", "push", "-u", "-m", "Rift stash") }
    func popStash() { runOperation("stash", "pop") }

    func continueOperation() {
        guard let operation else { return }
        switch operation {
        case .cherryPick: runOperation("cherry-pick", "--continue")
        case .rebase: runOperation("rebase", "--continue")
        case .merge: runOperation("commit", "--no-edit")
        case .revert: runOperation("revert", "--continue")
        }
    }

    func abortOperation() {
        guard let operation else { return }
        switch operation {
        case .cherryPick: runOperation("cherry-pick", "--abort")
        case .rebase: runOperation("rebase", "--abort")
        case .merge: runOperation("merge", "--abort")
        case .revert: runOperation("revert", "--abort")
        }
    }

    func resolve(_ file: String, using side: String?) {
        guard let root else { return }
        do {
            if let side { _ = try git(at: root, "checkout", side, "--", file) }
            _ = try git(at: root, "add", "--", file)
            refresh()
        } catch {
            refresh()
            errorMessage = error.localizedDescription
        }
    }

    private func runOperation(_ arguments: String...) {
        guard let root else { return }
        var operationError: String?
        do {
            _ = try git(at: root, arguments)
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

    private func detectOperation(at root: URL) -> GitOperation? {
        func gitPath(_ name: String) -> URL? {
            guard let path = try? git(at: root, "rev-parse", "--path-format=absolute", "--git-path", name)
                .trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
            return URL(fileURLWithPath: path)
        }
        let files = FileManager.default
        let exists: (URL) -> Bool = { files.fileExists(atPath: $0.path()) }
        if ["rebase-merge", "rebase-apply"].compactMap(gitPath).contains(where: exists) { return .rebase }
        if gitPath("CHERRY_PICK_HEAD").map(exists) == true { return .cherryPick }
        if gitPath("MERGE_HEAD").map(exists) == true { return .merge }
        if gitPath("REVERT_HEAD").map(exists) == true { return .revert }
        return nil
    }

    private func gitAllowingEmptyHistory(at root: URL) -> String {
        (try? git(
            at: root,
            "log", "-n", "100", "--date=iso-strict",
            "--pretty=format:%H%x1f%an%x1f%aI%x1f%s%x1e"
        )) ?? ""
    }

    private func parseStatus(_ output: String) -> [FileChange] {
        output.split(separator: "\n").compactMap { line in
            guard line.count >= 4 else { return nil }
            let chars = Array(line)
            return FileChange(indexStatus: chars[0], worktreeStatus: chars[1], path: String(chars.dropFirst(3)))
        }
    }

    private func parseLog(_ output: String) -> [Commit] {
        let formatter = ISO8601DateFormatter()
        return output.split(separator: "\u{1e}").compactMap { record in
            let fields = record.split(separator: "\u{1f}", maxSplits: 3).map(String.init)
            guard fields.count == 4 else { return nil }
            return Commit(id: fields[0], author: fields[1], date: formatter.date(from: fields[2]), subject: fields[3])
        }
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
