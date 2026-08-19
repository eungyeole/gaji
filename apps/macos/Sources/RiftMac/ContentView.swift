import AppKit
import CryptoKit
import SwiftUI

struct WorkspaceView: View {
    @Environment(WorkspaceStore.self) private var workspace

    var body: some View {
        ContentView()
            .environment(workspace.selectedRepository)
            .id(workspace.selectedTabID)
    }
}

private struct RepositoryTabBar: View {
    @Environment(WorkspaceStore.self) private var workspace

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(workspace.tabs) { tab in
                    HStack(spacing: 7) {
                        Button {
                            workspace.select(tab.id)
                        } label: {
                            HStack(spacing: 7) {
                                if !tab.repository.changes.isEmpty ||
                                   !tab.repository.commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Circle().fill(.orange).frame(width: 7, height: 7)
                                }
                                Text(tab.repository.title)
                                    .lineLimit(1)
                                    .frame(maxWidth: 150)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if workspace.tabs.count > 1 {
                            Button {
                                workspace.close(tab.id)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.caption2.weight(.semibold))
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(
                        workspace.selectedTabID == tab.id
                            ? Color.accentColor.opacity(0.14) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 9)
                    )
                }
                Button(action: workspace.newTab) {
                    Image(systemName: "plus")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.borderless)
                .help("New Repository Tab")
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .scrollIndicators(.hidden)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }
}

struct ContentView: View {
    @Environment(RepositoryStore.self) private var repository
    @Environment(WorkspaceStore.self) private var workspace
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        @Bindable var repository = repository

        Group {
            if repository.root == nil {
                VStack(spacing: 0) {
                    RepositoryTabBar()
                    WelcomeView()
                }
            } else {
                VStack(spacing: 0) {
                    if repository.operation != nil {
                        ConflictBar()
                        Divider()
                    }
                    NavigationSplitView(columnVisibility: $columnVisibility) {
                        SidebarView()
                            .navigationSplitViewColumnWidth(min: 210, ideal: 250, max: 320)
                    } detail: {
                        VStack(spacing: 0) {
                            RepositoryTabBar()
                            HSplitView {
                                Group {
                                    if repository.selectedFile != nil {
                                        FileDiffView()
                                    } else {
                                        CommitList(selection: $repository.selection)
                                    }
                                }
                                .frame(minWidth: 420, maxWidth: .infinity)
                                Group {
                                    if repository.selection != nil {
                                        CommitInspector()
                                    } else {
                                        WorkingCopyInspector()
                                    }
                                }
                                .frame(minWidth: 300, idealWidth: 360, maxWidth: 480)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(repository.title)
        .toolbar {
            ToolbarItemGroup {
                Button(action: repository.refresh) {
                    Label("Refresh", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                }
                .disabled(repository.root == nil)
                Button(action: workspace.chooseRepository) {
                    Label("Open Repository", systemImage: "folder")
                }
                Button(action: repository.fetch) {
                    Label("Fetch", systemImage: "arrow.down.circle")
                }
                .disabled(repository.root == nil)
                Button(action: repository.pull) {
                    Label("Pull", systemImage: "arrow.down.to.line")
                }
                .disabled(repository.root == nil)
                Button(action: repository.push) {
                    Label("Push", systemImage: "arrow.up.to.line")
                }
                .disabled(repository.root == nil)
                Menu {
                    Button("Stash All Changes", action: repository.stash)
                    Button("Pop Latest Stash", action: repository.popStash)
                        .disabled(repository.stashes.isEmpty)
                    if !repository.stashes.isEmpty {
                        Divider()
                        ForEach(repository.stashes) { stash in
                            Menu(stash.subject) {
                                Button("Apply") { repository.applyStash(stash.index, pop: false) }
                                Button("Pop") { repository.applyStash(stash.index, pop: true) }
                                Button("Drop", role: .destructive) { repository.dropStash(stash.index) }
                            }
                        }
                    }
                } label: {
                    Label("Stash", systemImage: "shippingbox")
                }
                .disabled(repository.root == nil)
            }
        }
        .sheet(isPresented: $repository.showsCreateBranch) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Create Branch").font(.title2.bold())
                TextField("Branch name", text: $repository.newBranchName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(repository.createBranch)
                HStack {
                    Spacer()
                    Button("Cancel") { repository.showsCreateBranch = false }
                        .keyboardShortcut(.cancelAction)
                    Button("Create and Switch", action: repository.createBranch)
                        .buttonStyle(.glassProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(repository.newBranchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(24)
            .frame(width: 420)
        }
        .sheet(isPresented: $repository.showsClone) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Clone Repository").font(.title2.bold())
                TextField("Repository URL", text: $repository.cloneURL)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    TextField("Destination", text: $repository.cloneDestination)
                        .textFieldStyle(.roundedBorder)
                    Button("Choose…", action: repository.chooseCloneDestination)
                }
                HStack {
                    Spacer()
                    Button("Cancel") { repository.showsClone = false }
                        .keyboardShortcut(.cancelAction)
                    Button("Clone", action: repository.cloneRepository)
                        .buttonStyle(.glassProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(
                            repository.cloneURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                            repository.cloneDestination.isEmpty
                        )
                }
            }
            .padding(24)
            .frame(width: 560)
        }
        .sheet(isPresented: $repository.showsInteractiveRebase) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Interactive Rebase onto \(repository.rebaseUpstream)")
                    .font(.title2.bold())
                Text("Reorder commits and choose how each one should be replayed.")
                    .foregroundStyle(.secondary)
                List {
                    ForEach(Array(repository.rebaseSteps.enumerated()), id: \.element.id) { index, step in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(step.subject).fontWeight(.medium)
                                Text(String(step.commit.prefix(10)))
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Picker("Action", selection: Binding(
                                get: { repository.rebaseSteps[index].action },
                                set: { repository.rebaseSteps[index].action = $0 }
                            )) {
                                Text("Pick").tag("pick")
                                Text("Reword").tag("reword")
                                Text("Edit").tag("edit")
                                Text("Squash").tag("squash")
                                Text("Fixup").tag("fixup")
                                Text("Drop").tag("drop")
                            }
                            .labelsHidden()
                            .frame(width: 120)
                            Button { repository.moveRebaseStep(index, by: -1) } label: {
                                Image(systemName: "arrow.up")
                            }
                            .disabled(index == 0)
                            Button { repository.moveRebaseStep(index, by: 1) } label: {
                                Image(systemName: "arrow.down")
                            }
                            .disabled(index == repository.rebaseSteps.count - 1)
                        }
                    }
                }
                HStack {
                    Spacer()
                    Button("Cancel") { repository.showsInteractiveRebase = false }
                    Button("Start Rebase", action: repository.startInteractiveRebase)
                        .buttonStyle(.glassProminent)
                        .disabled(repository.rebaseSteps.isEmpty)
                }
            }
            .padding(24)
            .frame(minWidth: 720, minHeight: 560)
        }
        .sheet(isPresented: $repository.showsAddRemote) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Add Remote").font(.title2.bold())
                TextField("Name", text: $repository.newRemoteName)
                    .textFieldStyle(.roundedBorder)
                TextField("URL", text: $repository.newRemoteURL)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Spacer()
                    Button("Cancel") { repository.showsAddRemote = false }
                    Button("Add", action: repository.addRemote)
                        .buttonStyle(.glassProminent)
                        .disabled(
                            repository.newRemoteName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                            repository.newRemoteURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        )
                }
            }
            .padding(24)
            .frame(width: 480)
        }
        .sheet(isPresented: Binding(
            get: { repository.taggingCommit != nil },
            set: { if !$0 { repository.taggingCommit = nil } }
        )) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Create Tag").font(.title2.bold())
                Text(repository.taggingCommit?.subject ?? "")
                    .foregroundStyle(.secondary)
                TextField("Tag name", text: $repository.newTagName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(repository.createTag)
                HStack {
                    Spacer()
                    Button("Cancel") { repository.taggingCommit = nil }
                    Button("Create", action: repository.createTag)
                        .buttonStyle(.glassProminent)
                        .disabled(repository.newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(24)
            .frame(width: 440)
        }
        .sheet(isPresented: Binding(
            get: { repository.blameFile != nil },
            set: { if !$0 { repository.blameFile = nil } }
        )) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(repository.blameFile ?? "File History").font(.title2.bold())
                    Spacer()
                    Button("Done") { repository.blameFile = nil }
                }
                TabView {
                    List(repository.blameLines) { line in
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(line.lineNumber)")
                                .frame(width: 44, alignment: .trailing)
                                .foregroundStyle(.secondary)
                            Text(String(line.commit.prefix(8)))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.tint)
                            Text(line.author).frame(width: 130, alignment: .leading).lineLimit(1)
                            Text(line.content)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                    .tabItem { Label("Blame", systemImage: "person.text.rectangle") }
                    List(repository.fileHistory) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.subject).fontWeight(.medium)
                            Text("\(entry.author) · \(String(entry.id.prefix(10)))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tabItem { Label("History", systemImage: "clock") }
                }
            }
            .padding(20)
            .frame(minWidth: 900, minHeight: 620)
        }
        .sheet(isPresented: $repository.showsAddWorktree) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Add Worktree").font(.title2.bold())
                Picker("Branch", selection: $repository.worktreeBranch) {
                    Text("Choose a branch").tag("")
                    ForEach(repository.branches.filter {
                        !repository.checkedOutWorktreeBranches.contains($0)
                    }, id: \.self) { Text($0).tag($0) }
                }
                HStack {
                    TextField("Destination", text: $repository.worktreeDestination)
                        .textFieldStyle(.roundedBorder)
                    Button("Choose…", action: repository.chooseWorktreeDestination)
                }
                HStack {
                    Spacer()
                    Button("Cancel") { repository.showsAddWorktree = false }
                    Button("Add", action: repository.addWorktree)
                        .buttonStyle(.glassProminent)
                        .disabled(repository.worktreeBranch.isEmpty || repository.worktreeDestination.isEmpty)
                }
            }
            .padding(24)
            .frame(width: 540)
        }
        .sheet(isPresented: Binding(
            get: { repository.renamingBranch != nil },
            set: { if !$0 { repository.renamingBranch = nil } }
        )) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Rename Branch").font(.title2.bold())
                TextField("New name", text: $repository.renamedBranch)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(repository.renameBranch)
                HStack {
                    Spacer()
                    Button("Cancel") { repository.renamingBranch = nil }
                    Button("Rename", action: repository.renameBranch)
                        .buttonStyle(.glassProminent)
                        .disabled(repository.renamedBranch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(24)
            .frame(width: 440)
        }
        .confirmationDialog(
            "Delete branch \(repository.deletingBranch ?? "")?",
            isPresented: Binding(
                get: { repository.deletingBranch != nil },
                set: { if !$0 { repository.deletingBranch = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Branch", role: .destructive, action: repository.deleteBranch)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Git will refuse to delete a branch whose commits are not merged.")
        }
        .sheet(isPresented: Binding(
            get: { repository.conflictFile != nil },
            set: { if !$0 { repository.conflictFile = nil } }
        )) {
            MergeEditorView()
                .environment(repository)
        }
        .confirmationDialog(
            "Hard reset to \(repository.pendingHardReset?.subject ?? "commit")?",
            isPresented: Binding(
                get: { repository.pendingHardReset != nil },
                set: { if !$0 { repository.pendingHardReset = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let commit = repository.pendingHardReset {
                Button("Discard Changes and Reset", role: .destructive) {
                    repository.reset(to: commit, mode: "--hard")
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All uncommitted tracked-file changes will be lost. This cannot be undone by Rift.")
        }
        .confirmationDialog(
            "Discard uncommitted changes?",
            isPresented: Binding(
                get: { repository.pendingDiscardFiles != nil },
                set: { if !$0 { repository.pendingDiscardFiles = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Discard Changes", role: .destructive, action: repository.confirmDiscard)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Changes in \(repository.pendingDiscardFiles?.count ?? 0) tracked file(s) will be permanently lost.")
        }
        .alert("Couldn’t Open Repository", isPresented: Binding(
            get: { repository.errorMessage != nil },
            set: { if !$0 { repository.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(repository.errorMessage ?? "Unknown error")
        }
    }
}

private struct ConflictBar: View {
    @Environment(RepositoryStore.self) private var repository

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: repository.conflicts.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(repository.conflicts.isEmpty ? .green : .orange)
                Text(repository.operation?.rawValue ?? "Git operation").font(.headline)
                Text(repository.conflicts.isEmpty ? "Ready to continue" : "Resolve \(repository.conflicts.count) conflict(s)")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Abort", role: .destructive, action: repository.abortOperation)
                Button("Continue", action: repository.continueOperation)
                    .buttonStyle(.glassProminent)
                    .disabled(!repository.conflicts.isEmpty)
            }
            ForEach(repository.conflicts, id: \.self) { file in
                HStack {
                    Image(systemName: "doc.badge.ellipsis")
                    Text(file).lineLimit(1)
                    Spacer()
                    Button("Merge Editor") { repository.openConflictEditor(file) }
                    Button("Use Current") { repository.resolve(file, using: "--ours") }
                    Button("Use Incoming") { repository.resolve(file, using: "--theirs") }
                    Button("Mark Resolved") { repository.resolve(file, using: nil) }
                }
                .font(.callout)
            }
        }
        .padding(12)
        .background(.orange.opacity(0.06))
    }
}

private struct MergeEditorView: View {
    @Environment(RepositoryStore.self) private var repository

    var body: some View {
        @Bindable var repository = repository

        VStack(spacing: 0) {
            HStack {
                Text("Resolve \(repository.conflictFile ?? "Conflict")").font(.title2.bold())
                Spacer()
                Button("Cancel") { repository.conflictFile = nil }
                Button("Save and Mark Resolved", action: repository.saveConflictResult)
                    .buttonStyle(.glassProminent)
            }
            .padding()
            Divider()
            HStack(spacing: 0) {
                ConflictPane(title: "Base", content: repository.conflictBase)
                Divider()
                ConflictPane(title: "Current", content: repository.conflictOurs)
                Divider()
                ConflictPane(title: "Incoming", content: repository.conflictTheirs)
            }
            .frame(minHeight: 240)
            Divider()
            HStack {
                Text("Result").font(.headline)
                Spacer()
                Button("Use Current") { repository.conflictResult = repository.conflictOurs }
                Button("Use Incoming") { repository.conflictResult = repository.conflictTheirs }
            }
            .padding(.horizontal)
            TextEditor(text: $repository.conflictResult)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 260)
                .padding([.horizontal, .bottom])
        }
        .frame(minWidth: 1000, minHeight: 680)
    }
}

private struct ConflictPane: View {
    let title: String
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline).padding(.horizontal)
            ScrollView([.horizontal, .vertical]) {
                Text(content.isEmpty ? "Not present" : content)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical)
    }
}

private struct WelcomeView: View {
    @Environment(RepositoryStore.self) private var repository

    var body: some View {
        ZStack {
            LinearGradient(colors: [.indigo.opacity(0.28), .clear, .cyan.opacity(0.18)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 56, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                Text("Rift").font(.system(size: 42, weight: .bold, design: .rounded))
                Text("A native home for your Git repositories").foregroundStyle(.secondary)
                HStack {
                    Button("Create…", action: repository.createRepository)
                    Button("Clone…") { repository.showsClone = true }
                    Button("Open Repository…", action: repository.chooseRepository)
                        .buttonStyle(.glassProminent)
                }
                .controlSize(.large)
                if !repository.recentRepositories.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Recent Repositories")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        ForEach(repository.recentRepositories.prefix(5), id: \.self) { path in
                            Button {
                                repository.openRecent(path)
                            } label: {
                                Label(URL(fileURLWithPath: path).lastPathComponent, systemImage: "clock")
                                    .frame(maxWidth: 260, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .help(path)
                        }
                    }
                    .padding(.top, 8)
                }
            }
            .padding(42)
            .glassEffect(.regular, in: .rect(cornerRadius: 28))
        }
    }
}

private struct SidebarView: View {
    @Environment(RepositoryStore.self) private var repository
    @Environment(WorkspaceStore.self) private var workspace
    @State private var selectedItem: String?
    @State private var branchQuery = ""

    private var matchingLocalBranches: [String] { matching(repository.branches) }
    private var matchingRemoteBranches: [String] { matching(repository.remoteBranches) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search branches", text: $branchQuery)
                    .textFieldStyle(.plain)
                if !branchQuery.isEmpty {
                    Button { branchQuery = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
                .padding(.horizontal, 9)
                .frame(height: 28)
                .glassEffect(.regular, in: .rect(cornerRadius: 8))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
            List(selection: $selectedItem) {
                Section {
                    if matchingLocalBranches.contains(repository.branch) {
                        BranchRow(name: repository.branch, isCurrent: true)
                            .tag("local:\(repository.branch)")
                            .contextMenu { LocalBranchMenu(branch: repository.branch) }
                    }
                    BranchTreeRows(
                        nodes: branchTree(matchingLocalBranches.filter { $0 != repository.branch }),
                        scope: .local
                    )
                } header: {
                    sectionHeader("Local") { repository.showsCreateBranch = true }
                }

                Section {
                    BranchTreeRows(nodes: branchTree(matchingRemoteBranches), scope: .remote)
                } header: {
                    sectionHeader("Remote") { repository.showsAddRemote = true }
                }

                Section {
                ForEach(repository.worktrees) { worktree in
                    let name = worktree.branch ?? URL(fileURLWithPath: worktree.path).lastPathComponent
                    HStack(spacing: 7) {
                        Circle()
                            .fill(worktree.path == repository.root?.path() ? Color.green : Color.secondary.opacity(0.35))
                            .frame(width: 7, height: 7)
                        Text(name).lineLimit(1)
                        Spacer(minLength: 6)
                        let folder = URL(fileURLWithPath: worktree.path).lastPathComponent
                        if folder != name {
                            Text(folder)
                                .font(.caption2)
                                .opacity(0.65)
                                .lineLimit(1)
                        }
                    }
                    .frame(height: 22)
                    .tag("worktree:\(worktree.path)")
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        workspace.openRepository(URL(fileURLWithPath: worktree.path))
                    }
                    .help(worktree.path)
                    .contextMenu {
                        Button("Open Worktree in Tab") {
                            workspace.openRepository(URL(fileURLWithPath: worktree.path))
                        }
                        if worktree.path != repository.root?.path() {
                            Button("Remove Worktree", role: .destructive) {
                                repository.removeWorktree(worktree.path)
                            }
                        }
                    }
                }
                } header: {
                    sectionHeader("Worktrees") { repository.showsAddWorktree = true }
                }
            }
            .listStyle(.sidebar)
            .controlSize(.small)
            .environment(\.defaultMinListRowHeight, 22)
            .tint(Color(red: 0.04, green: 0.52, blue: 1.0))
            .scrollContentBackground(.hidden)
            .onAppear { selectedItem = "local:\(repository.branch)" }
            .onChange(of: repository.branch) { _, branch in
                selectedItem = "local:\(branch)"
            }
        }
    }

    private func matching(_ branches: [String]) -> [String] {
        let query = branchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? branches : branches.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    private func sectionHeader(_ title: String, action: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Button(action: action) {
                Image(systemName: "plus")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.borderless)
            .help("Add \(title)")
        }
        .frame(height: 24)
    }
}

private struct BranchTreeNode: Identifiable {
    let id: String
    let name: String
    let branch: String?
    let children: [BranchTreeNode]
}

private func branchTree(_ branches: [String], prefix: String = "") -> [BranchTreeNode] {
    let groups = Dictionary(grouping: branches) { $0.split(separator: "/", maxSplits: 1).first.map(String.init) ?? $0 }
    return groups.keys.map { name in
        let fullName = prefix.isEmpty ? name : "\(prefix)/\(name)"
        let suffixes = groups[name, default: []].compactMap { branch -> String? in
            let parts = branch.split(separator: "/", maxSplits: 1)
            return parts.count == 2 ? String(parts[1]) : nil
        }
        return BranchTreeNode(
            id: suffixes.isEmpty ? "branch:\(fullName)" : "folder:\(fullName)",
            name: name,
            branch: suffixes.isEmpty ? fullName : nil,
            children: branchTree(suffixes, prefix: fullName)
        )
    }.sorted {
        if $0.children.isEmpty != $1.children.isEmpty { return !$0.children.isEmpty }
        return $0.name.localizedStandardCompare($1.name) == .orderedAscending
    }
}

private struct BranchTreeRows: View {
    enum Scope { case local, remote }

    @Environment(RepositoryStore.self) private var repository
    let nodes: [BranchTreeNode]
    let scope: Scope

    var body: some View {
        ForEach(nodes) { node in
            if let branch = node.branch {
                BranchRow(name: node.name, isCurrent: scope == .local && branch == repository.branch)
                    .tag("\(scope == .local ? "local" : "remote"):\(branch)")
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { switchTo(branch) }
                    .contextMenu { branchMenu(branch) }
            } else {
                DisclosureGroup {
                    BranchTreeRows(nodes: node.children, scope: scope)
                } label: {
                    Label(node.name, systemImage: scope == .remote && node.id.count == "folder:".count + node.name.count ? "externaldrive" : "folder")
                        .lineLimit(1)
                }
            }
        }
    }

    private func switchTo(_ branch: String) {
        scope == .local ? repository.switchBranch(branch) : repository.switchRemoteBranch(branch)
    }

    @ViewBuilder
    private func branchMenu(_ branch: String) -> some View {
        Button(scope == .local ? "Switch" : "Check Out") { switchTo(branch) }
            .disabled(scope == .local && branch == repository.branch)
        Divider()
        Button("Merge into \(repository.branch)") { repository.merge(branch) }
            .disabled(scope == .local && branch == repository.branch)
        Button("Rebase \(repository.branch) onto this") { repository.rebase(onto: branch) }
            .disabled(scope == .local && branch == repository.branch)
        Button("Interactive Rebase…") { repository.prepareInteractiveRebase(onto: branch) }
            .disabled(scope == .local && branch == repository.branch)
        Divider()
        if scope == .local {
            Button("Add Worktree…") {
                repository.worktreeBranch = branch
                repository.showsAddWorktree = true
            }
            .disabled(repository.checkedOutWorktreeBranches.contains(branch))
            Button("Rename…") { repository.beginRenameBranch(branch) }
            Button("Delete…", role: .destructive) { repository.deletingBranch = branch }
                .disabled(branch == repository.branch)
        } else if let remote = branch.split(separator: "/").first.map(String.init) {
            Button("Fetch \(remote)") { repository.fetch(remote) }
        }
    }
}

private struct LocalBranchMenu: View {
    @Environment(RepositoryStore.self) private var repository
    let branch: String

    var body: some View {
        Button("Add Worktree…") {
            repository.worktreeBranch = branch
            repository.showsAddWorktree = true
        }
        .disabled(repository.checkedOutWorktreeBranches.contains(branch))
        Button("Rename…") { repository.beginRenameBranch(branch) }
    }
}

private struct BranchRow: View {
    let name: String
    let isCurrent: Bool

    var body: some View {
        HStack {
            Text(name).lineLimit(1)
            Spacer(minLength: 4)
            if isCurrent {
                Text("HEAD")
                    .font(.caption2.weight(.semibold))
                    .opacity(0.7)
            }
        }
        .font(.callout)
        .frame(height: 22)
    }
}

private struct WorkingCopyInspector: View {
    @Environment(RepositoryStore.self) private var repository

    var body: some View {
        @Bindable var repository = repository

        VStack(spacing: 0) {
            HStack {
                Text("Changes").font(.headline)
                Spacer()
                if !repository.unstagedChanges.isEmpty {
                    Menu {
                        Button("Discard All Changes…", role: .destructive) {
                            repository.requestDiscard(repository.unstagedChanges.map(\.path))
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .frame(width: 22, height: 22)
                    }
                    .menuIndicator(.hidden)
                    .buttonStyle(.glass)
                    .fixedSize()
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 42)
            .background(.bar)

            VSplitView {
                ChangeBucket(staged: false)
                    .frame(minHeight: 150, maxHeight: .infinity)
                ChangeBucket(staged: true)
                    .frame(minHeight: 150, maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("Commit").font(.headline)
                    Spacer()
                    Menu {
                        Toggle("Amend Previous Commit", isOn: $repository.commitAmend)
                        Toggle("Sign Commit", isOn: $repository.commitSign)
                        Toggle("Add Signed-off-by", isOn: $repository.commitSignoff)
                    } label: {
                        Label("Options", systemImage: "slider.horizontal.3")
                    }
                    .menuIndicator(.hidden)
                    .buttonStyle(.glass)
                    .fixedSize()
                }
                TextField("Summary", text: $repository.commitMessage, axis: .vertical)
                    .lineLimit(2...5)
                    .textFieldStyle(.roundedBorder)
                Button {
                    repository.createCommit()
                } label: {
                    Text("Commit to \(repository.branch)")
                        .frame(maxWidth: .infinity)
                }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(
                        (repository.stagedChanges.isEmpty && !repository.commitAmend) ||
                        repository.commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
            }
            .padding(14)
            .background(.bar)
        }
    }
}

private struct CommitInspector: View {
    @Environment(RepositoryStore.self) private var repository

    private var commit: Commit? {
        repository.commits.first { $0.id == repository.selection }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let commit {
                VStack(alignment: .leading, spacing: 6) {
                    Button {
                        repository.closeFileDetails()
                        repository.selection = nil
                    } label: {
                        Label("Changes", systemImage: "chevron.left")
                    }
                    .buttonStyle(.borderless)
                    Text(commit.subject).font(.headline).lineLimit(2)
                    HStack(spacing: 6) {
                        Text(commit.author)
                        if let date = commit.date { Text("·"); Text(date, style: .relative) }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Text(String(commit.id.prefix(12)))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(.bar)
            }
            Divider()
            HStack {
                Text("Changed Files").font(.subheadline.weight(.semibold))
                Text("\(repository.selectedCommitFiles.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(.bar)

            if repository.selectedCommitFilesLoading {
                ProgressView("Loading files…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if repository.selectedCommitFiles.isEmpty {
                ContentUnavailableView("No Changed Files", systemImage: "doc")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(repository.selectedCommitFiles) { change in
                    HStack(spacing: 8) {
                        Text(commitStatusMark(change.status))
                            .font(.system(.callout, design: .monospaced, weight: .bold))
                            .foregroundStyle(commitStatusColor(change.status))
                            .frame(width: 14)
                        VStack(alignment: .leading, spacing: 1) {
                            Text((change.path as NSString).lastPathComponent).lineLimit(1)
                            let parent = (change.path as NSString).deletingLastPathComponent
                            if !parent.isEmpty && parent != "." {
                                Text(parent).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { repository.selectCommitFile(change) }
                    .help(change.path)
                    .listRowInsets(.init(top: 4, leading: 8, bottom: 4, trailing: 8))
                    .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func commitStatusMark(_ status: String) -> String {
        if status.hasPrefix("A") { return "+" }
        if status.hasPrefix("D") { return "−" }
        if status.hasPrefix("R") { return "R" }
        return "M"
    }

    private func commitStatusColor(_ status: String) -> Color {
        if status.hasPrefix("A") { return .green }
        if status.hasPrefix("D") { return .red }
        if status.hasPrefix("R") { return .blue }
        return .orange
    }
}

private struct ChangeBucket: View {
    @Environment(RepositoryStore.self) private var repository
    let staged: Bool

    private var changes: [FileChange] {
        staged ? repository.stagedChanges : repository.unstagedChanges
    }

    private var fileSelection: Binding<String?> {
        Binding(
            get: {
                repository.selectedFileIsStaged == staged ? repository.selectedFile : nil
            },
            set: { path in
                guard let path, let change = changes.first(where: { $0.path == path }) else { return }
                repository.select(change, staged: staged)
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(staged ? "Staged" : "Unstaged").font(.subheadline.weight(.semibold))
                Text("\(changes.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Button(staged ? "Unstage All" : "Stage All") {
                    staged ? repository.unstageAll() : repository.stageAll()
                }
                .buttonStyle(.borderless)
                .disabled(changes.isEmpty)
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(.bar)
            if changes.isEmpty {
                Text(staged ? "No staged files" : "No unstaged files")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: fileSelection) {
                    ForEach(changes) { change in
                    HStack(spacing: 8) {
                        Text(statusMark(change.statusLabel))
                            .font(.system(.callout, design: .monospaced, weight: .bold))
                            .foregroundStyle(statusColor(change.statusLabel))
                            .frame(width: 14)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(fileName(change.path))
                                .lineLimit(1)
                            if let parent = parentPath(change.path) {
                                Text(parent)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .help(change.path)
                        Button {
                            staged ? repository.unstage(change.path) : repository.stage(change.path)
                        } label: {
                            Text(staged ? "−" : "+")
                                .font(.system(.body, design: .rounded, weight: .medium))
                                .frame(width: 18, height: 18)
                        }
                        .buttonStyle(.borderless)
                        .help(staged ? "Unstage file" : "Stage file")
                    }
                    .tag(change.path)
                    .contentShape(Rectangle())
                    .listRowInsets(.init(top: 4, leading: 8, bottom: 4, trailing: 8))
                    .listRowSeparator(.hidden)
                    .contextMenu {
                        Button(staged ? "Unstage File" : "Stage File") {
                            staged ? repository.unstage(change.path) : repository.stage(change.path)
                        }
                        if !staged, change.worktreeStatus != "?" {
                            Button("Discard Changes…", role: .destructive) {
                                repository.requestDiscard([change.path])
                            }
                        }
                        Divider()
                        Button("Blame and File History") { repository.openBlame(change.path) }
                    }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private func statusMark(_ status: String) -> String {
        switch status {
        case "A", "U": "+"
        case "D": "−"
        case "R": "R"
        default: "M"
        }
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "A", "U": .green
        case "D": .red
        case "R": .blue
        default: .orange
        }
    }

    private func fileName(_ path: String) -> String {
        (path as NSString).lastPathComponent
    }

    private func parentPath(_ path: String) -> String? {
        let parent = (path as NSString).deletingLastPathComponent
        return parent.isEmpty || parent == "." ? nil : parent
    }
}

private struct FileDiffView: View {
    @Environment(RepositoryStore.self) private var repository

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button("History", action: repository.closeFileDetails)
                    .buttonStyle(.borderless)
                Divider().frame(height: 18)
                Text(repository.selectedFile ?? "Diff").font(.headline)
                Spacer()
                if repository.selectedFileCommit == nil, let file = repository.selectedFile {
                    if !repository.selectedFileIsStaged,
                       let change = repository.changes.first(where: { $0.path == file }),
                       change.worktreeStatus != "?" {
                        Button("Discard…", role: .destructive) { repository.requestDiscard([file]) }
                    }
                    Button(repository.selectedFileIsStaged ? "Unstage File" : "Stage File") {
                        repository.selectedFileIsStaged ? repository.unstage(file) : repository.stage(file)
                    }
                }
            }
            .padding()
            Divider()
            if repository.selectedFileIsLoading {
                ProgressView("Loading diff…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if repository.selectedFileDiff.isEmpty {
                ContentUnavailableView("No Text Diff", systemImage: "doc",
                    description: Text("The file may be untracked, binary, or unchanged in this comparison."))
            } else {
                VStack(spacing: 0) {
                    if repository.selectedFileCommit == nil, !repository.selectedHunks.isEmpty {
                        ScrollView(.horizontal) {
                            LazyHStack(spacing: 8) {
                                ForEach(repository.selectedHunks) { hunk in
                                    Button {
                                        repository.apply(hunk)
                                    } label: {
                                        Text("\(repository.selectedFileIsStaged ? "Unstage" : "Stage") \(hunk.header)")
                                            .font(.system(.caption, design: .monospaced))
                                            .lineLimit(1)
                                    }
                                    .buttonStyle(.glass)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                        }
                        .scrollIndicators(.hidden)
                        .frame(height: 44)
                        .background(.bar)
                        Divider()
                    }
                    CodeTextView(text: repository.selectedFileDiff)
                }
            }
        }
    }
}

private struct CommitList: View {
    @Environment(RepositoryStore.self) private var repository
    @Binding var selection: Commit.ID?

    private var visibleRows: [CommitGraphRow] {
        let query = repository.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let rows = commitGraphRows(repository.commits)
        guard !query.isEmpty else { return rows }
        return rows.filter {
            $0.commit.subject.localizedCaseInsensitiveContains(query) ||
            $0.commit.author.localizedCaseInsensitiveContains(query) ||
            $0.commit.id.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        @Bindable var repository = repository
        let rows = visibleRows
        let laneCount = rows.map { max($0.topLanes.count, $0.bottomLanes.count) }.max() ?? 1
        let laneSpacing = laneCount > 1 ? min(16, 104 / CGFloat(laneCount - 1)) : 16

        List(rows, selection: $selection) { row in
            let commit = row.commit
            HStack(spacing: 8) {
                CommitReferences(references: commit.references)
                CommitGraph(row: row, spacing: laneSpacing)
                Text(commit.subject)
                    .foregroundStyle(.primary)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .layoutPriority(1)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(height: 24)
            .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
            .listRowSeparator(.hidden)
            .contextMenu {
                Button("Cherry-Pick \(String(commit.id.prefix(8)))") {
                    repository.cherryPick(commit)
                }
                .disabled(repository.operation != nil)
                Button("Revert Commit") { repository.revert(commit) }
                    .disabled(repository.operation != nil)
                Button("Create Tag…") { repository.taggingCommit = commit }
                Menu("Reset Current Branch") {
                    Button("Soft") { repository.reset(to: commit, mode: "--soft") }
                    Button("Mixed") { repository.reset(to: commit, mode: "--mixed") }
                    Button("Hard…", role: .destructive) { repository.pendingHardReset = commit }
                }
                Button("Copy Commit Hash") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(commit.id, forType: .string)
                }
            }
        }
        .environment(\.defaultMinListRowHeight, 24)
        .searchable(text: $repository.searchText, prompt: "Search commits")
        .task(id: selection) { repository.selectCommit(selection) }
    }

}

private struct CommitHoverDetails: ViewModifier {
    let commit: Commit
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .onHover { isHovering = $0 }
            .popover(isPresented: $isHovering, arrowEdge: .trailing) {
                VStack(alignment: .leading, spacing: 9) {
                    Text(commit.subject)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    LabeledContent("Author") {
                        Text(commit.author)
                    }
                    if !commit.authorEmail.isEmpty {
                        LabeledContent("Email") {
                            Text(commit.authorEmail).textSelection(.enabled)
                        }
                    }
                    LabeledContent("Date") {
                        Text(commit.date?.formatted(date: .long, time: .standard) ?? "Unknown")
                    }
                    LabeledContent("Commit") {
                        Text(commit.id)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    if !commit.parents.isEmpty {
                        LabeledContent("Parents") {
                            Text(commit.parents.map { String($0.prefix(10)) }.joined(separator: ", "))
                                .font(.system(.caption, design: .monospaced))
                        }
                    }
                }
                .padding(14)
                .frame(width: 380)
            }
    }
}

private struct CommitReferences: View {
    @Environment(RepositoryStore.self) private var repository
    let references: [String]

    var body: some View {
        HStack(spacing: 3) {
            if let reference = references.first {
                Text(clean(reference))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(reference.hasPrefix("tag: ") ? Color.orange : Color.accentColor, in: Capsule())
                    .contentShape(Capsule())
                    .onTapGesture(count: 2, perform: checkOut)
                if references.count > 1 {
                    Text("+\(references.count - 1)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 118, alignment: .trailing)
        .help(references.joined(separator: "\n"))
    }

    private func clean(_ reference: String) -> String {
        reference
            .replacingOccurrences(of: "HEAD -> ", with: "")
            .replacingOccurrences(of: "tag: ", with: "")
    }

    private func checkOut() {
        let names = references.map(clean)
        if let branch = names.first(where: { repository.branches.contains($0) }) {
            repository.switchBranch(branch)
        } else if let branch = names.first(where: { repository.remoteBranches.contains($0) }) {
            repository.switchRemoteBranch(branch)
        }
    }
}

private struct CommitAvatar: View {
    let commit: Commit

    var body: some View {
        AsyncImage(url: avatarURL) { phase in
            if case let .success(image) = phase {
                image
                    .resizable()
                    .scaledToFill()
                    .background(.background, in: Circle())
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.accentColor, lineWidth: 1.5))
            } else {
                Circle()
                    .fill(Color.accentColor.opacity(0.22))
                    .overlay {
                        Text(String(commit.author.prefix(1)).uppercased())
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.tint)
                    }
                    .overlay(Circle().stroke(Color.accentColor, lineWidth: 1.5))
            }
        }
        .frame(width: 18, height: 18)
    }

    private var avatarURL: URL? {
        let email = commit.authorEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !email.isEmpty else { return nil }
        if email.hasSuffix("@users.noreply.github.com") {
            let local = email.split(separator: "@", maxSplits: 1).first.map(String.init) ?? ""
            let username = local.split(separator: "+").last.map(String.init) ?? local
            if !username.isEmpty { return URL(string: "https://github.com/\(username).png?size=48") }
        }
        let digest = Insecure.MD5.hash(data: Data(email.utf8)).map { String(format: "%02x", $0) }.joined()
        return URL(string: "https://www.gravatar.com/avatar/\(digest)?d=404&s=48")
    }
}

private struct CommitGraphRow: Identifiable {
    let commit: Commit
    let topLanes: [String]
    let bottomLanes: [String]
    let nodeLane: Int
    var id: String { commit.id }
}

private func commitGraphRows(_ commits: [Commit]) -> [CommitGraphRow] {
    var lanes: [String] = []
    return commits.map { commit in
        if !lanes.contains(commit.id) { lanes.insert(commit.id, at: 0) }
        let top = lanes
        let nodeLane = lanes.firstIndex(of: commit.id) ?? 0
        lanes.remove(at: nodeLane)
        for parent in commit.parents { lanes.removeAll { $0 == parent } }
        lanes.insert(contentsOf: commit.parents, at: min(nodeLane, lanes.count))
        return CommitGraphRow(commit: commit, topLanes: top, bottomLanes: lanes, nodeLane: nodeLane)
    }
}

private struct CommitGraph: View {
    let row: CommitGraphRow
    let spacing: CGFloat
    private let colors: [Color] = [.blue, .purple, .orange, .green, .pink, .cyan, .indigo, .mint]

    var body: some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, size in
                let centerY = size.height / 2
                let color = colors[row.nodeLane % colors.count]

                for (topLane, hash) in row.topLanes.enumerated() where hash != row.commit.id {
                    guard let bottomLane = row.bottomLanes.firstIndex(of: hash) else { continue }
                    var path = Path()
                    path.move(to: point(topLane, -1))
                    path.addCurve(
                        to: point(bottomLane, size.height + 1),
                        control1: point(topLane, size.height * 0.45),
                        control2: point(bottomLane, size.height * 0.55)
                    )
                    context.stroke(path, with: .color(colors[topLane % colors.count].opacity(0.72)), lineWidth: 2)
                }

                var incoming = Path()
                incoming.move(to: point(row.nodeLane, -1))
                incoming.addLine(to: point(row.nodeLane, centerY))
                context.stroke(incoming, with: .color(color), lineWidth: 2)

                for parent in row.commit.parents {
                    guard let lane = row.bottomLanes.firstIndex(of: parent) else { continue }
                    var path = Path()
                    path.move(to: point(row.nodeLane, centerY))
                    path.addCurve(
                        to: point(lane, size.height + 1),
                        control1: point(row.nodeLane, size.height * 0.55),
                        control2: point(lane, size.height * 0.72)
                    )
                    context.stroke(path, with: .color(colors[lane % colors.count]), lineWidth: 2)
                }

                let node = CGRect(x: x(row.nodeLane) - 5, y: centerY - 5, width: 10, height: 10)
                context.fill(Path(ellipseIn: node), with: .color(color))
                context.stroke(Path(ellipseIn: node), with: .color(.white.opacity(0.75)), lineWidth: 1.5)
            }
            CommitAvatar(commit: row.commit)
                .modifier(CommitHoverDetails(commit: row.commit))
                .offset(x: x(row.nodeLane) - 9, y: 3)
        }
        .frame(width: 120)
        .frame(height: 24)
        .accessibilityHidden(true)
    }

    private func x(_ lane: Int) -> CGFloat { CGFloat(lane) * spacing + 8 }
    private func point(_ lane: Int, _ y: CGFloat) -> CGPoint { CGPoint(x: x(lane), y: y) }
}
