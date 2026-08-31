import AppKit
import CryptoKit
import SwiftUI

private enum GajiUI {
    static let panelInset: CGFloat = 8
    static let sectionSpacing: CGFloat = 8
    static let headerHeight: CGFloat = 40
    static let sectionHeaderHeight: CGFloat = 32
    static let rowRadius: CGFloat = 8
    static let hoverOpacity = 0.055
    static let selectionOpacity = 0.16
    static let fieldOpacity = 0.045
    static let statusOpacity = 0.82
}

struct WorkspaceView: View {
    @Environment(WorkspaceStore.self) private var workspace

    var body: some View {
        ContentView()
            .environment(workspace.selectedRepository)
            .id(workspace.selectedTabID)
            .onChange(of: workspace.selectedRepository.root) { _, _ in workspace.persistTabs() }
    }
}

private struct ThinSplitViewInstaller: NSViewRepresentable {
    func makeNSView(context: Context) -> InstallerView { InstallerView() }

    func updateNSView(_ view: InstallerView, context: Context) { view.install() }

    final class InstallerView: NSView {
        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            install()
        }

        func install() {
            var ancestor = superview
            while let current = ancestor {
                if let splitView = current as? NSSplitView {
                    splitView.dividerStyle = .thin
                    splitView.needsDisplay = true
                    return
                }
                ancestor = current.superview
            }
        }
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
                            ? Color.accentColor.opacity(GajiUI.selectionOpacity) : Color.clear,
                        in: RoundedRectangle(cornerRadius: GajiUI.rowRadius)
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
        .overlay(alignment: .bottom) {
            if workspace.selectedRepository.isBusy {
                ProgressView()
                    .progressViewStyle(.linear)
                    .controlSize(.mini)
                    .frame(height: 1)
                    .clipped()
                    .allowsHitTesting(false)
                    .accessibilityLabel(Text(workspace.selectedRepository.busyMessage ?? "Working"))
                    .transition(.opacity)
            } else {
                Divider()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: workspace.selectedRepository.isBusy)
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
                            .background(ThinSplitViewInstaller())
                            .navigationSplitViewColumnWidth(min: 210, ideal: 250, max: 320)
                    } detail: {
                        VStack(spacing: 0) {
                            RepositoryTabBar()
                            HSplitView {
                                Group {
                                    if repository.selectedFile != nil {
                                        FileDiffView()
                                    } else {
                                        CommitList()
                                    }
                                }
                                .frame(minWidth: 420, maxWidth: .infinity)
                                Group {
                                    if repository.selectedStash != nil {
                                        StashInspector()
                                    } else if repository.selection != nil {
                                        CommitInspector()
                                    } else {
                                        WorkingCopyInspector()
                                    }
                                }
                                .frame(minWidth: 300, idealWidth: 360, maxWidth: 480)
                            }
                            .background(ThinSplitViewInstaller())
                        }
                    }
                }
            }
        }
        .navigationTitle(repository.title)
        .toolbar {
            ToolbarItem {
                Menu {
                    Section("Pull Strategy") {
                        ForEach(PullBehavior.allCases, id: \.self) { behavior in
                            Button {
                                repository.pull(behavior)
                            } label: {
                                if repository.pullBehavior == behavior {
                                    Label(behavior.title, systemImage: "checkmark")
                                } else {
                                    Text(behavior.title)
                                }
                            }
                        }
                    }
                    Divider()
                    Button("Fetch All", action: repository.fetch)
                    Button("Refresh View", action: repository.refresh)
                } label: {
                    Label("Pull", systemImage: "arrow.down.to.line")
                } primaryAction: {
                    repository.pull()
                }
                .help("Pull using \(repository.pullBehavior.title)")
                .disabled(repository.root == nil || repository.isBusy)
            }
            ToolbarItem {
                Button(action: repository.push) {
                    Label("Push", systemImage: "arrow.up.to.line")
                }
                .help("Push the current branch")
                .disabled(repository.root == nil || repository.isBusy)
            }
            ToolbarItem {
                ControlGroup {
                    Button(action: repository.stash) {
                        Label("Stash", systemImage: "tray.and.arrow.down")
                    }
                    .help("Stash working copy changes")
                    .disabled(repository.root == nil || repository.isBusy)
                    Button(action: repository.popStash) {
                        Label("Pop", systemImage: "tray.and.arrow.up")
                    }
                    .help("Pop the latest stash")
                    .disabled(repository.root == nil || repository.stashes.isEmpty || repository.isBusy)
                }
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
            Text("All uncommitted tracked-file changes will be lost. This cannot be undone by Gaji.")
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
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("Start with a repository").font(.title2.weight(.semibold))
                Text("Open an existing project or create a new one.")
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Button(action: repository.chooseRepository) {
                    Label("Open", systemImage: "folder")
                }
                .buttonStyle(.borderedProminent)
                Button { repository.showsClone = true } label: {
                    Label("Clone", systemImage: "square.and.arrow.down")
                }
                Button(action: repository.createRepository) {
                    Label("Create", systemImage: "plus")
                }
            }
            .controlSize(.large)
            if !repository.recentRepositories.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recent")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(repository.recentRepositories.prefix(6), id: \.self) { path in
                        RecentRepositoryRow(path: path)
                    }
                }
                .padding(.top, 4)
            }
        }
        .frame(width: 440)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

private struct RecentRepositoryRow: View {
    @Environment(RepositoryStore.self) private var repository
    let path: String
    @State private var isHovering = false

    var body: some View {
        Button { repository.openRecent(path) } label: {
            HStack(spacing: 10) {
                Image(systemName: "folder").foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(URL(fileURLWithPath: path).lastPathComponent).lineLimit(1)
                    Text(path).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .opacity(isHovering ? 1 : 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Color.primary.opacity(isHovering ? GajiUI.hoverOpacity : 0),
                in: RoundedRectangle(cornerRadius: GajiUI.rowRadius)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(path)
    }
}

private struct SidebarView: View {
    @Environment(RepositoryStore.self) private var repository
    @Environment(WorkspaceStore.self) private var workspace
    @State private var selectedItem: String?
    @State private var branchQuery = ""

    private var matchingLocalBranches: [String] { matching(repository.branches) }
    private var matchingRemoteBranches: [String] { matching(repository.remoteBranches) }
    private var isSearchingBranches: Bool {
        !branchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

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
                .glassEffect(.regular, in: .rect(cornerRadius: GajiUI.rowRadius))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
            List(selection: $selectedItem) {
                Section {
                    if matchingLocalBranches.contains(repository.branch) {
                        BranchRow(name: repository.branch, fullName: repository.branch, isCurrent: true)
                            .tag("local:\(repository.branch)")
                            .contextMenu { LocalBranchMenu(branch: repository.branch) }
                    }
                    BranchTreeRows(
                        nodes: branchNodes(matchingLocalBranches.filter { $0 != repository.branch }),
                        scope: .local
                    )
                } header: {
                    sectionHeader("Local") { repository.showsCreateBranch = true }
                }

                Section {
                    BranchTreeRows(nodes: branchNodes(matchingRemoteBranches), scope: .remote)
                } header: {
                    sectionHeader("Remote") { repository.showsAddRemote = true }
                }

                if !repository.stashes.isEmpty {
                    Section("Stashes") {
                        ForEach(repository.stashes) { stash in
                            HStack(spacing: 7) {
                                Image(systemName: "shippingbox")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 14)
                                Text(stash.subject)
                                    .lineLimit(1)
                                Spacer(minLength: 6)
                                Text("#\(stash.index)")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(height: 22)
                            .tag("stash:\(stash.id)")
                            .contentShape(Rectangle())
                            .help(stash.reference)
                            .contextMenu {
                                Button("Apply") { repository.applyStash(stash.index, pop: false) }
                                    .disabled(repository.operation != nil || repository.isBusy)
                                Button("Pop") { repository.applyStash(stash.index, pop: true) }
                                    .disabled(repository.operation != nil || repository.isBusy)
                                Divider()
                                Button("Drop", role: .destructive) { repository.dropStash(stash.index) }
                                    .disabled(repository.operation != nil || repository.isBusy)
                            }
                        }
                    }
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
            .onChange(of: selectedItem) { _, item in
                guard let item, item.hasPrefix("stash:") else { return }
                let identifier = String(item.dropFirst("stash:".count))
                guard let stash = repository.stashes.first(where: { $0.id == identifier }),
                      repository.selectedStash?.reference != stash.reference else { return }
                repository.selectStash(stash)
            }
        }
    }

    private func matching(_ branches: [String]) -> [String] {
        let query = branchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? branches : branches.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    private func branchNodes(_ branches: [String]) -> [BranchTreeNode] {
        guard isSearchingBranches else { return branchTree(branches) }
        return branches.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.map { branch in
            BranchTreeNode(id: "branch:\(branch)", name: branch, branch: branch, children: [])
        }
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
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .tint(Color(nsColor: .secondaryLabelColor))
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
        let hasExactBranch = groups[name, default: []].contains { branch in
            branch.split(separator: "/", maxSplits: 1).count == 1
        }
        let suffixes = groups[name, default: []].compactMap { branch -> String? in
            let parts = branch.split(separator: "/", maxSplits: 1)
            return parts.count == 2 ? String(parts[1]) : nil
        }
        return BranchTreeNode(
            id: suffixes.isEmpty ? "branch:\(fullName)" : "folder:\(fullName)",
            name: name,
            branch: hasExactBranch ? fullName : nil,
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
            if node.children.isEmpty, let branch = node.branch {
                BranchRow(name: node.name, fullName: branch, isCurrent: scope == .local && branch == repository.branch)
                    .tag("\(scope == .local ? "local" : "remote"):\(branch)")
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { switchTo(branch) }
                    .contextMenu { branchMenu(branch) }
            } else {
                DisclosureGroup {
                    BranchTreeRows(nodes: node.children, scope: scope)
                } label: {
                    HStack(spacing: 6) {
                        Label(
                            node.name,
                            systemImage: scope == .remote && node.id.count == "folder:".count + node.name.count
                                ? "externaldrive" : "folder"
                        )
                        .lineLimit(1)
                        .truncationMode(.middle)
                        if scope == .local, node.branch == repository.branch {
                            Spacer(minLength: 4)
                            Text("HEAD")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .tag(node.branch.map { "\(scope == .local ? "local" : "remote"):\($0)" } ?? node.id)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    if let branch = node.branch { switchTo(branch) }
                }
                .help(node.id.replacingOccurrences(of: "folder:", with: ""))
                .contextMenu {
                    if let branch = node.branch { branchMenu(branch) }
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
    let fullName: String
    let isCurrent: Bool

    var body: some View {
        HStack {
            Text(name)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            if isCurrent {
                Text("HEAD")
                    .font(.caption2.weight(.semibold))
                    .opacity(0.7)
            }
        }
        .font(.callout)
        .frame(height: 22)
        .help(fullName)
    }
}

private struct WorkingCopyInspector: View {
    @Environment(RepositoryStore.self) private var repository

    var body: some View {
        @Bindable var repository = repository

        VStack(spacing: GajiUI.sectionSpacing) {
            VStack(spacing: 8) {
                ChangeBucket(staged: false)
                    .frame(minHeight: 120, maxHeight: .infinity)
                ChangeBucket(staged: true)
                    .frame(minHeight: 120, maxHeight: .infinity)
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
                        Image(systemName: "slider.horizontal.3")
                            .frame(width: 22, height: 22)
                    }
                    .menuIndicator(.hidden)
                    .buttonStyle(.glass)
                    .fixedSize()
                }
                TextField("Summary", text: $repository.commitMessage, axis: .vertical)
                    .lineLimit(2...5)
                    .textFieldStyle(.plain)
                    .padding(9)
                    .background(Color.primary.opacity(GajiUI.fieldOpacity), in: RoundedRectangle(cornerRadius: GajiUI.rowRadius))
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
            .padding(12)
            .glassEffect(.regular, in: .rect(cornerRadius: 14))
        }
        .padding(GajiUI.panelInset)
    }
}

private struct CommitInspector: View {
    @Environment(RepositoryStore.self) private var repository

    private var commit: Commit? {
        repository.commits.first { $0.id == repository.selection }
    }

    private var selectedCommits: [Commit] {
        repository.commits.filter { repository.selectedCommitIDs.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: GajiUI.sectionSpacing) {
            HStack {
                Button {
                    repository.closeFileDetails()
                    repository.clearCommitSelection()
                } label: {
                    Label("Back to Changes", systemImage: "chevron.left")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.glass)
                .help("Back to Changes")
                Spacer()
            }
            .padding(.horizontal, 4)
            .frame(height: GajiUI.headerHeight)

            if selectedCommits.count > 1 {
                HStack {
                    Text("\(selectedCommits.count) commits selected")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Button("Squash…") { repository.prepareSquash(selectedCommits) }
                    Button("Cherry-Pick") { repository.cherryPick(selectedCommits) }
                        .buttonStyle(.glassProminent)
                }
                .disabled(repository.operation != nil || repository.isBusy)
                .padding(.horizontal, 4)
            }

            if let commit {
                VStack(alignment: .leading, spacing: 6) {
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
                .padding(12)
                .glassEffect(.regular, in: .rect(cornerRadius: 14))
            }
            VStack(spacing: 0) {
                HStack {
                    Text("Files").font(.subheadline.weight(.semibold))
                    Text("\(repository.selectedCommitFiles.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .frame(height: GajiUI.sectionHeaderHeight)

                if repository.selectedCommitFilesLoading {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if repository.selectedCommitFiles.isEmpty {
                    ContentUnavailableView("No Changed Files", systemImage: "doc")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(repository.selectedCommitFiles) { change in
                                CommitFileRow(
                                    change: change,
                                    isSelected: repository.selectedFile == change.path
                                )
                            }
                        }
                        .padding(4)
                    }
                }
            }
        }
        .padding(GajiUI.panelInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

}

private struct StashInspector: View {
    @Environment(RepositoryStore.self) private var repository

    var body: some View {
        VStack(spacing: GajiUI.sectionSpacing) {
            HStack {
                Button(action: repository.closeStashDetails) {
                    Label("Back to Changes", systemImage: "chevron.left")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.glass)
                .help("Back to Changes")
                Spacer()
            }
            .padding(.horizontal, 4)
            .frame(height: GajiUI.headerHeight)

            if let stash = repository.selectedStash {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .top) {
                        Text(stash.subject).font(.headline).lineLimit(2)
                        Spacer(minLength: 8)
                        Menu {
                            Button("Apply") { repository.applyStash(stash.index, pop: false) }
                                .disabled(repository.operation != nil || repository.isBusy)
                            Button("Pop") { repository.applyStash(stash.index, pop: true) }
                                .disabled(repository.operation != nil || repository.isBusy)
                            Divider()
                            Button("Drop", role: .destructive) { repository.dropStash(stash.index) }
                                .disabled(repository.operation != nil || repository.isBusy)
                        } label: {
                            Image(systemName: "ellipsis")
                                .frame(width: 22, height: 22)
                        }
                        .menuIndicator(.hidden)
                        .buttonStyle(.glass)
                        .fixedSize()
                    }
                    Text(stash.reference)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .glassEffect(.regular, in: .rect(cornerRadius: 14))
            }

            VStack(spacing: 0) {
                HStack {
                    Text("Files").font(.subheadline.weight(.semibold))
                    Text("\(repository.selectedStashFiles.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .frame(height: GajiUI.sectionHeaderHeight)

                if repository.selectedStashFilesLoading {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if repository.selectedStashFiles.isEmpty {
                    ContentUnavailableView("No Changed Files", systemImage: "doc")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(repository.selectedStashFiles) { change in
                                StashFileRow(
                                    change: change,
                                    isSelected: repository.selectedFile == change.path
                                )
                            }
                        }
                        .padding(4)
                    }
                }
            }
        }
        .padding(GajiUI.panelInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct FileChangeRowContent<Trailing: View>: View {
    let status: String
    let path: String
    let isSelected: Bool
    let isHovering: Bool
    let trailing: Trailing

    init(
        status: String,
        path: String,
        isSelected: Bool,
        isHovering: Bool,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.status = status
        self.path = path
        self.isSelected = isSelected
        self.isHovering = isHovering
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 8) {
            StatusBadge(status: status)
            Text(path)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(
            rowBackground,
            in: RoundedRectangle(cornerRadius: GajiUI.rowRadius)
        )
        .overlay {
            RoundedRectangle(cornerRadius: GajiUI.rowRadius)
                .strokeBorder(hoverBorder, lineWidth: 1)
        }
    }

    private var rowBackground: Color {
        if isSelected {
            return Color.accentColor.opacity(isHovering ? 0.24 : GajiUI.selectionOpacity)
        }
        return Color.primary.opacity(isHovering ? GajiUI.hoverOpacity : 0)
    }

    private var hoverBorder: Color {
        guard isHovering else { return .clear }
        return isSelected ? Color.accentColor.opacity(0.7) : Color.primary.opacity(0.12)
    }
}

private struct FileRowHoverTracker: NSViewRepresentable {
    @Binding var isHovering: Bool

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onHover = { isHovering = $0 }
        return view
    }

    func updateNSView(_ view: TrackingView, context: Context) {
        view.onHover = { isHovering = $0 }
    }

    final class TrackingView: NSView {
        var onHover: (Bool) -> Void = { _ in }
        private var area: NSTrackingArea?

        override func updateTrackingAreas() {
            if let area { removeTrackingArea(area) }
            let area = NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                owner: self
            )
            addTrackingArea(area)
            self.area = area
            super.updateTrackingAreas()
        }

        override func mouseEntered(with event: NSEvent) { onHover(true) }
        override func mouseExited(with event: NSEvent) { onHover(false) }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

private struct StashFileRow: View {
    @Environment(RepositoryStore.self) private var repository
    let change: CoreCommitFileChange
    let isSelected: Bool
    @State private var isHovering = false

    var body: some View {
        FileChangeRowContent(
            status: change.status,
            path: change.path,
            isSelected: isSelected,
            isHovering: isHovering
        ) {
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .opacity(isHovering ? 1 : 0)
        }
        .background(FileRowHoverTracker(isHovering: $isHovering))
        .contentShape(Rectangle())
        .onTapGesture {
            isSelected ? repository.closeFileDetails() : repository.selectStashFile(change)
        }
        .help(change.path)
    }
}

private struct CommitFileRow: View {
    @Environment(RepositoryStore.self) private var repository
    let change: CoreCommitFileChange
    let isSelected: Bool
    @State private var isHovering = false

    var body: some View {
        FileChangeRowContent(
            status: change.status,
            path: change.path,
            isSelected: isSelected,
            isHovering: isHovering
        ) {
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .opacity(isHovering ? 1 : 0)
        }
        .background(FileRowHoverTracker(isHovering: $isHovering))
        .contentShape(Rectangle())
        .onTapGesture {
            isSelected ? repository.closeFileDetails() : repository.selectCommitFile(change)
        }
        .help(change.path)
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
                if !staged, !changes.isEmpty {
                    Menu {
                        Button("Discard All…", role: .destructive) {
                            repository.requestDiscard(changes.map(\.path))
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .frame(width: 20, height: 20)
                    }
                    .menuIndicator(.hidden)
                    .buttonStyle(.borderless)
                    .fixedSize()
                }
            }
            .padding(.horizontal, 12)
            .frame(height: GajiUI.sectionHeaderHeight)
            if changes.isEmpty {
                Text(staged ? "No staged files" : "No unstaged files")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                    ForEach(changes) { change in
                        ChangeFileRow(
                            change: change,
                            staged: staged,
                            isSelected: fileSelection.wrappedValue == change.path
                        )
                    }
                    }
                    .padding(4)
                }
            }
        }
    }
}

private struct ChangeFileRow: View {
    @Environment(RepositoryStore.self) private var repository
    let change: FileChange
    let staged: Bool
    let isSelected: Bool
    @State private var isHovering = false

    var body: some View {
        FileChangeRowContent(
            status: change.statusLabel,
            path: change.path,
            isSelected: isSelected,
            isHovering: isHovering
        ) {
            Button {
                staged ? repository.unstage(change.path) : repository.stage(change.path)
            } label: {
                Image(systemName: staged ? "minus" : "plus")
                    .font(.caption.weight(.semibold))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.glass)
            .opacity(isHovering ? 1 : 0)
            .allowsHitTesting(isHovering)
            .help(staged ? "Unstage file" : "Stage file")
        }
        .background(FileRowHoverTracker(isHovering: $isHovering))
        .contentShape(Rectangle())
        .onTapGesture {
            isSelected ? repository.closeFileDetails() : repository.select(change, staged: staged)
        }
        .help(change.path)
        .contextMenu {
            Button(staged ? "Unstage File" : "Stage File") {
                staged ? repository.unstage(change.path) : repository.stage(change.path)
            }
            if !staged, change.worktreeStatus != "?" {
                Button("Discard Changes…", role: .destructive) { repository.requestDiscard([change.path]) }
            }
            Divider()
            Button("Blame and File History") { repository.openBlame(change.path) }
        }
    }

}

private struct StatusBadge: View {
    let status: String

    var body: some View {
        Text(mark)
            .font(.system(.caption2, design: .monospaced, weight: .bold))
            .foregroundStyle(color)
            .frame(width: 16, height: 20)
    }

    private var mark: String {
        if status.hasPrefix("A") || status.hasPrefix("U") { return "+" }
        if status.hasPrefix("D") { return "−" }
        if status.hasPrefix("R") { return "R" }
        return "M"
    }

    private var color: Color {
        if status.hasPrefix("A") || status.hasPrefix("U") { return .green.opacity(GajiUI.statusOpacity) }
        if status.hasPrefix("D") { return .red.opacity(GajiUI.statusOpacity) }
        if status.hasPrefix("R") { return .blue.opacity(GajiUI.statusOpacity) }
        return .orange.opacity(GajiUI.statusOpacity)
    }
}

private struct FileDiffView: View {
    @Environment(RepositoryStore.self) private var repository

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button(action: repository.closeFileDetails) {
                    Label(repository.selectedStash == nil ? "Back to History" : "Back to Stash", systemImage: "chevron.left")
                        .labelStyle(.iconOnly)
                }
                    .buttonStyle(.borderless)
                    .help(repository.selectedStash == nil ? "Back to History" : "Back to Stash")
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
            .padding(.horizontal, 12)
            .frame(height: 44)
            Divider()
            if repository.selectedFileIsLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if repository.selectedFileDiff.isEmpty {
                ContentUnavailableView("No Text Diff", systemImage: "doc",
                    description: Text("The file may be untracked, binary, or unchanged in this comparison."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct CommitList: View {
    @Environment(RepositoryStore.self) private var repository
    @State private var graphRowsCache = CommitGraphRowsCache()

    private var isFiltering: Bool {
        !repository.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func visibleRows(in graphRows: [CommitGraphRow]) -> [CommitGraphRow] {
        let query = repository.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return graphRows }
        return graphRows.filter {
            $0.commit.subject.localizedCaseInsensitiveContains(query) ||
            $0.commit.author.localizedCaseInsensitiveContains(query) ||
            $0.commit.id.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        @Bindable var repository = repository
        let rows = visibleRows(in: graphRowsCache.rows(for: repository.commits))
        let visibleIDs = rows.map(\.id)
        let selection = Binding<Set<Commit.ID>>(
            get: { repository.selectedCommitIDs },
            set: { repository.updateCommitSelection($0, ordered: visibleIDs) }
        )
        let laneCount = isFiltering
            ? 1
            : rows.map { max($0.topLanes.count, $0.bottomLanes.count) }.max() ?? 1
        let laneSpacing = laneCount > 1 ? min(13, 84 / CGFloat(laneCount - 1)) : 13
        let graphWidth: CGFloat = 98

        List(rows, selection: selection) { row in
            let commit = row.commit
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Color.clear
                        .frame(width: 118, height: 24)
                        .overlay(alignment: .leading) {
                            CommitReferences(commit: commit)
                        }
                        .zIndex(2)
                    CommitGraph(
                        row: row,
                        spacing: laneSpacing,
                        width: graphWidth,
                        hidesConnections: isFiltering
                    )
                }
                .zIndex(1)
                Text(commit.subject)
                    .foregroundStyle(.primary)
                    .fontWeight(commit.isStash ? .semibold : .medium)
                    .lineLimit(1)
                    .help(commit.subject)
                    .layoutPriority(2)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(height: 24)
            .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
            .listRowSeparator(.hidden)
            .listRowBackground(commit.isStash ? Color.purple.opacity(0.07) : Color.clear)
            .contextMenu {
                if commit.isStash {
                    if let stash = repository.stash(matching: commit.id) {
                        Button("View Stash Details", systemImage: "shippingbox") {
                            repository.selectStash(stash)
                        }
                        Button("Apply Stash") { repository.applyStash(stash.index, pop: false) }
                            .disabled(repository.operation != nil || repository.isBusy)
                        Button("Pop Stash") { repository.applyStash(stash.index, pop: true) }
                            .disabled(repository.operation != nil || repository.isBusy)
                    }
                    Divider()
                    Button("Copy Stash Commit Hash") { copyCommitHash(commit) }
                } else {
                    let selected = repository.selectedCommitIDs.contains(commit.id)
                        ? rows.map(\.commit).filter { repository.selectedCommitIDs.contains($0.id) }
                        : [commit]
                    Button(selected.count > 1 ? "Cherry-Pick \(selected.count) Commits" : "Cherry-Pick \(String(commit.id.prefix(8)))") {
                        repository.cherryPick(selected)
                    }
                    .disabled(repository.operation != nil)
                    if selected.count > 1 {
                        Button("Squash \(selected.count) Commits…") {
                            repository.prepareSquash(selected)
                        }
                        .disabled(repository.operation != nil)
                        Divider()
                    }
                    Button("Revert Commit") { repository.revert(commit) }
                        .disabled(repository.operation != nil)
                    Button("Create Tag…") { repository.taggingCommit = commit }
                    Menu("Reset Current Branch") {
                        Button("Soft") { repository.reset(to: commit, mode: "--soft") }
                        Button("Mixed") { repository.reset(to: commit, mode: "--mixed") }
                        Button("Hard…", role: .destructive) { repository.pendingHardReset = commit }
                    }
                    Button("Copy Commit Hash") { copyCommitHash(commit) }
                }
            }
            .onAppear {
                guard !isFiltering, commit.id == rows.last?.id else { return }
                repository.loadMoreCommits()
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 24)
        .searchable(text: $repository.searchText, prompt: "Search commits")
        .overlay(alignment: .bottomTrailing) {
            if repository.isLoadingMoreCommits {
                ProgressView()
                    .controlSize(.small)
                    .padding(8)
                    .background(.regularMaterial, in: Circle())
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
        .onChange(of: visibleIDs) { _, ids in
            let visibleSelection = repository.selectedCommitIDs.intersection(ids)
            guard visibleSelection != repository.selectedCommitIDs else { return }
            repository.updateCommitSelection(visibleSelection, ordered: ids)
        }
        .task(id: repository.selection) { repository.selectCommit(repository.selection) }
    }

    private func copyCommitHash(_ commit: Commit) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(commit.id, forType: .string)
    }

}

private enum CommitReferenceKind: Int {
    case stash
    case current
    case local
    case tag
    case remote
    case other

    var title: String {
        switch self {
        case .stash: "Stash"
        case .current: "Current branch"
        case .local: "Local branch"
        case .tag: "Tag"
        case .remote: "Remote branch"
        case .other: "Reference"
        }
    }

    var icon: String {
        switch self {
        case .stash: "shippingbox.fill"
        case .current: "location.fill"
        case .local: "arrow.triangle.branch"
        case .tag: "tag.fill"
        case .remote: "cloud.fill"
        case .other: "bookmark.fill"
        }
    }

    var tint: Color {
        switch self {
        case .stash: .purple
        case .current: .green
        case .local: .accentColor
        case .tag: .orange
        case .remote: .indigo
        case .other: .gray
        }
    }
}

private struct CommitReferencePresentation: Identifiable {
    let rawValue: String
    let name: String
    let kind: CommitReferenceKind
    let isSuppressed: Bool
    let order: Int
    var id: String { "\(order):\(rawValue)" }
}

private struct CommitReferences: View {
    @Environment(RepositoryStore.self) private var repository
    let commit: Commit
    @State private var isHovered = false

    var body: some View {
        let allReferences = presentations
        let visibleReferences = compact(allReferences)

        if let primary = visibleReferences.first {
            let additionalCount = max(0, visibleReferences.count - 1)
            let collapsedTextWidth: CGFloat = additionalCount > 0 ? 48 : 78
            let expandedTextWidth: CGFloat = additionalCount > 0 ? 220 : 250
            let isCurrentBranch = primary.kind == .current
            let chipColor = Color.blue
            let idleChipColor = chipColor.opacity(isHovered ? 0.92 : 0.72)
            let idleBorderColor = chipColor.opacity(isHovered ? 0.72 : 0.38)
            let expands = isHovered && needsExpansion(
                for: primary,
                collapsedWidth: collapsedTextWidth
            )
            Button {
                showReferenceMenu(allReferences)
            } label: {
                HStack(spacing: 3) {
                    HStack(spacing: 4) {
                        Image(systemName: primary.kind.icon)
                            .font(.caption2.weight(.semibold))
                        Text(displayName(for: primary))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .multilineTextAlignment(.leading)
                            .frame(
                                maxWidth: expands ? expandedTextWidth : collapsedTextWidth,
                                alignment: .leading
                            )
                        Image(systemName: "chevron.down")
                            .font(.system(size: 7, weight: .bold))
                            .opacity(0.72)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isCurrentBranch ? Color.white : idleChipColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        isCurrentBranch ? chipColor : Color(nsColor: .windowBackgroundColor),
                        in: Capsule()
                    )
                    .overlay {
                        Capsule()
                            .strokeBorder(
                                isCurrentBranch ? Color.clear : idleBorderColor,
                                lineWidth: isCurrentBranch ? 0 : 0.8
                            )
                    }

                    if additionalCount > 0 {
                        Text("+\(additionalCount)")
                            .font(.caption2.monospacedDigit().weight(.bold))
                            .foregroundStyle(isCurrentBranch ? Color.white : idleChipColor)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 3)
                            .background(
                                isCurrentBranch ? chipColor : Color(nsColor: .windowBackgroundColor),
                                in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .strokeBorder(
                                        isCurrentBranch ? Color.white.opacity(0.22) : idleBorderColor,
                                        lineWidth: isCurrentBranch ? 0.5 : 0.8
                                    )
                            }
                            .accessibilityLabel("\(additionalCount) more references")
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(helpText(for: allReferences))
            .frame(
                width: expands
                    ? expandedWidth(for: primary, additionalCount: additionalCount)
                    : 114,
                height: 22,
                alignment: .leading
            )
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.14)) {
                    isHovered = hovering
                }
            }
            .help(helpText(for: allReferences))
            .zIndex(isHovered ? 1 : 0)
        }
    }

    private var presentations: [CommitReferencePresentation] {
        let values = if commit.referenceDetails.isEmpty {
            commit.references.enumerated().map { index, reference in
                let name = clean(reference)
                return CommitReferencePresentation(
                    rawValue: reference,
                    name: name,
                    kind: kind(of: reference, named: name),
                    isSuppressed: false,
                    order: index
                )
            }
        } else {
            commit.referenceDetails.enumerated().map { index, reference in
                CommitReferencePresentation(
                    rawValue: reference.fullName,
                    name: reference.name,
                    kind: kind(of: reference),
                    isSuppressed: reference.isSuppressed,
                    order: index
                )
            }
        }
        return values
        .sorted {
            if $0.kind.rawValue != $1.kind.rawValue { return $0.kind.rawValue < $1.kind.rawValue }
            return $0.order < $1.order
        }
    }

    private func compact(_ references: [CommitReferencePresentation]) -> [CommitReferencePresentation] {
        let localNames = Set(references.compactMap { reference in
            reference.kind == .local || reference.kind == .current ? reference.name : nil
        })
        return references.filter { reference in
            guard !reference.isSuppressed else { return false }
            guard reference.kind == .remote else { return true }
            if !commit.referenceDetails.isEmpty { return true }
            return !localNames.contains(localName(forRemote: reference.name))
        }
    }

    private func clean(_ reference: String) -> String {
        var name = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["HEAD -> ", "tag: ", "refs/heads/", "refs/remotes/", "refs/tags/"] where name.hasPrefix(prefix) {
            name.removeFirst(prefix.count)
            break
        }
        return name
    }

    private func kind(of reference: String, named name: String) -> CommitReferenceKind {
        let normalized = reference.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized == "stash" || normalized == "refs/stash" ||
            normalized.hasPrefix("stash@{") || normalized.hasPrefix("stash: ") {
            return .stash
        }
        if normalized == "head" { return .other }
        if normalized.hasPrefix("head -> ") { return .current }
        if normalized.hasPrefix("tag: ") || normalized.hasPrefix("refs/tags/") { return .tag }
        if normalized.hasPrefix("refs/heads/") || repository.branches.contains(name) { return .local }
        if normalized.hasPrefix("refs/remotes/") || repository.remoteBranches.contains(name) { return .remote }
        if let remote = name.split(separator: "/", maxSplits: 1).first.map(String.init),
           repository.remotes.contains(remote) {
            return .remote
        }
        return .other
    }

    private func kind(of reference: CommitReference) -> CommitReferenceKind {
        if reference.kind == "head" { return .other }
        if reference.isCurrent { return .current }
        return switch reference.kind {
        case "localBranch": .local
        case "remoteBranch": .remote
        case "tag": .tag
        case "stash": .stash
        default: .other
        }
    }

    private func localName(forRemote name: String) -> String {
        let parts = name.split(separator: "/", maxSplits: 1)
        return parts.count == 2 ? String(parts[1]) : name
    }

    private func displayName(for reference: CommitReferencePresentation) -> String {
        if reference.kind == .stash { return "Stash" }
        if reference.kind == .remote, reference.name.hasPrefix("origin/") {
            return String(reference.name.dropFirst("origin/".count))
        }
        return reference.name
    }

    private func needsExpansion(
        for reference: CommitReferencePresentation,
        collapsedWidth: CGFloat
    ) -> Bool {
        displayTextWidth(for: reference) > collapsedWidth
    }

    private func expandedWidth(
        for reference: CommitReferencePresentation,
        additionalCount: Int
    ) -> CGFloat {
        let countBadgeWidth: CGFloat = additionalCount > 0 ? 27 : 0
        return min(300, max(114, displayTextWidth(for: reference) + 46 + countBadgeWidth))
    }

    private func displayTextWidth(for reference: CommitReferencePresentation) -> CGFloat {
        let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        return ceil((displayName(for: reference) as NSString).size(withAttributes: [.font: font]).width)
    }

    private func showReferenceMenu(_ references: [CommitReferencePresentation]) {
        let event = NSApp.currentEvent
        guard let window = event?.window ?? NSApp.keyWindow ?? NSApp.mainWindow,
              let view = window.contentView else { return }

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.minimumWidth = 280
        var targets: [ReferenceMenuActionTarget] = []

        func addItem(
            title: String,
            systemImage: String,
            isEnabled: Bool = true,
            action: @escaping () -> Void
        ) {
            let target = ReferenceMenuActionTarget(action: action)
            let displayedTitle = truncatedMenuTitle(title, maxWidth: 350)
            let item = NSMenuItem(
                title: displayedTitle,
                action: #selector(ReferenceMenuActionTarget.performAction(_:)),
                keyEquivalent: ""
            )
            if displayedTitle != title { item.toolTip = title }
            item.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: nil)
            item.target = target
            item.isEnabled = isEnabled
            targets.append(target)
            menu.addItem(item)
        }

        for reference in references {
            switch reference.kind {
            case .current, .local:
                addItem(
                    title: "\(reference.kind.title): \(reference.name)",
                    systemImage: reference.kind.icon,
                    isEnabled: reference.name != repository.branch &&
                        repository.operation == nil && !repository.isBusy
                ) {
                    repository.switchBranch(reference.name)
                }
            case .remote:
                if reference.isSuppressed || reference.name.hasSuffix("/HEAD") {
                    let label = reference.name.hasSuffix("/HEAD") ? "Remote Default" : "Tracked Remote"
                    addItem(
                        title: "Copy \(label): \(reference.name)",
                        systemImage: "doc.on.doc"
                    ) {
                        copy(reference.name)
                    }
                } else {
                    addItem(
                        title: "Check Out Remote: \(reference.name)",
                        systemImage: reference.kind.icon,
                        isEnabled: repository.operation == nil && !repository.isBusy
                    ) {
                        repository.switchRemoteBranch(reference.name)
                    }
                }
            case .stash, .tag, .other:
                addItem(
                    title: "Copy \(reference.kind.title): \(reference.name)",
                    systemImage: reference.kind.icon
                ) {
                    copy(reference.name)
                }
            }
        }

        menu.addItem(.separator())
        addItem(title: "Copy All References", systemImage: "doc.on.doc") {
            copy(references.map(\.name).joined(separator: "\n"))
        }

        let location: NSPoint
        if let event, event.window === window {
            location = view.convert(event.locationInWindow, from: nil)
        } else {
            let windowLocation = window.convertPoint(fromScreen: NSEvent.mouseLocation)
            location = view.convert(windowLocation, from: nil)
        }
        _ = withExtendedLifetime(targets) {
            menu.popUp(positioning: nil, at: location, in: view)
        }
    }

    private func truncatedMenuTitle(_ title: String, maxWidth: CGFloat) -> String {
        let font = NSFont.menuFont(ofSize: 0)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        guard (title as NSString).size(withAttributes: attributes).width > maxWidth else {
            return title
        }

        let characters = Array(title)
        var lowerBound = 0
        var upperBound = characters.count
        while lowerBound < upperBound {
            let candidateLength = (lowerBound + upperBound + 1) / 2
            let candidate = String(characters.prefix(candidateLength)) + "…"
            if (candidate as NSString).size(withAttributes: attributes).width <= maxWidth {
                lowerBound = candidateLength
            } else {
                upperBound = candidateLength - 1
            }
        }
        return String(characters.prefix(lowerBound)) + "…"
    }

    private func helpText(for references: [CommitReferencePresentation]) -> String {
        references.map {
            let detail = if $0.name.hasSuffix("/HEAD") {
                " (remote default alias)"
            } else if $0.isSuppressed {
                " (tracks local branch)"
            } else {
                ""
            }
            return "\($0.kind.title): \($0.name)\(detail)"
        }
        .joined(separator: "\n")
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}

private final class ReferenceMenuActionTarget: NSObject {
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
    }

    @objc func performAction(_: Any?) { action() }
}

private struct GitHubCommitIdentity: Decodable, Sendable {
    struct Author: Decodable, Sendable {
        let avatarURL: URL

        private enum CodingKeys: String, CodingKey {
            case avatarURL = "avatar_url"
        }
    }

    let sha: String
    let author: Author?
}

private actor GitHubAvatarResolver {
    static let shared = GitHubAvatarResolver()
    private var cache: [String: [String: URL]] = [:]
    private var firstPageRequests: [String: Task<[String: URL], Never>] = [:]
    private var backfillRequests: [String: Task<[String: URL], Never>] = [:]
    private var commitRequests: [String: Task<URL?, Never>] = [:]
    private nonisolated static let authenticationToken = githubToken()

    func avatarURL(repository: String, commit: String) async -> URL? {
        if let avatar = cache[repository]?[commit] { return avatar }

        if cache[repository] == nil {
            let request = firstPageRequests[repository] ?? Task.detached(priority: .utility) {
                await Self.load(repository: repository, pages: [1])
            }
            let backfillRequest = backfillRequests[repository] ?? Task.detached(priority: .utility) {
                await Self.load(repository: repository, pages: Array(2...5))
            }
            firstPageRequests[repository] = request
            backfillRequests[repository] = backfillRequest
            let avatars = await request.value
            firstPageRequests[repository] = nil
            cache[repository, default: [:]].merge(avatars) { _, new in new }
            if let avatar = avatars[commit] { return avatar }
        }

        if let backfillRequest = backfillRequests[repository] {
            let avatars = await backfillRequest.value
            backfillRequests[repository] = nil
            cache[repository, default: [:]].merge(avatars) { _, new in new }
            if let avatar = avatars[commit] { return avatar }
        }

        let key = "\(repository):\(commit)"
        let request = commitRequests[key] ?? Task.detached(priority: .utility) {
            await Self.load(repository: repository, commit: commit)
        }
        commitRequests[key] = request
        let avatar = await request.value
        commitRequests[key] = nil
        if let avatar {
            cache[repository, default: [:]][commit] = avatar
        }
        return avatar
    }

    private nonisolated static func load(
        repository: String,
        pages: [Int]
    ) async -> [String: URL] {
        await withTaskGroup(of: [GitHubCommitIdentity].self) { group in
            for page in pages {
                group.addTask(priority: .utility) {
                    await loadPage(repository: repository, page: page)
                }
            }

            var avatars: [String: URL] = [:]
            for await commits in group {
                for commit in commits {
                    if let avatar = commit.author?.avatarURL { avatars[commit.sha] = avatar }
                }
            }
            return avatars
        }
    }

    private nonisolated static func loadPage(
        repository: String,
        page: Int
    ) async -> [GitHubCommitIdentity] {
        guard let url = URL(
            string: "https://api.github.com/repos/\(repository)/commits?per_page=100&page=\(page)"
        ) else { return [] }
        var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 8)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        if let authenticationToken {
            request.setValue("Bearer \(authenticationToken)", forHTTPHeaderField: "Authorization")
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }
            return try JSONDecoder().decode([GitHubCommitIdentity].self, from: data)
        } catch {
            return []
        }
    }

    private nonisolated static func load(repository: String, commit: String) async -> URL? {
        guard let url = URL(string: "https://api.github.com/repos/\(repository)/commits/\(commit)") else {
            return nil
        }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        if let authenticationToken {
            request.setValue("Bearer \(authenticationToken)", forHTTPHeaderField: "Authorization")
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            let decoder = JSONDecoder()
            return try decoder.decode(GitHubCommitIdentity.self, from: data).author?.avatarURL
        } catch {
            return nil
        }
    }

    private nonisolated static func githubToken() -> String? {
        let environment = ProcessInfo.processInfo.environment
        if let token = environment["GH_TOKEN"] ?? environment["GITHUB_TOKEN"], !token.isEmpty {
            return token
        }
        let process = Process()
        let output = Pipe()
        let candidates = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"]
        guard let executable = candidates.first(where: FileManager.default.fileExists(atPath:)) else { return nil }
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["auth", "token"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let token = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return token.isEmpty ? nil : token
        } catch {
            return nil
        }
    }
}

@MainActor
private final class AvatarImageCache {
    static let shared = AvatarImageCache()

    private let images = NSCache<NSURL, NSImage>()
    private var requests: [URL: Task<NSImage?, Never>] = [:]

    private init() {
        images.countLimit = 512
        images.totalCostLimit = 48 * 1_024 * 1_024
    }

    func cachedImage(for url: URL) -> NSImage? {
        images.object(forKey: url as NSURL)
    }

    func image(for url: URL) async -> NSImage? {
        if let image = cachedImage(for: url) { return image }
        if let request = requests[url] { return await request.value }

        let request = Task<NSImage?, Never> {
            var urlRequest = URLRequest(
                url: url,
                cachePolicy: .returnCacheDataElseLoad,
                timeoutInterval: 8
            )
            urlRequest.setValue("image/*", forHTTPHeaderField: "Accept")
            do {
                let (data, response) = try await URLSession.shared.data(for: urlRequest)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
                return NSImage(data: data)
            } catch {
                return nil
            }
        }
        requests[url] = request
        let image = await request.value
        requests[url] = nil
        if let image {
            let cost = image.representations.reduce(0) { result, representation in
                result + max(1, representation.pixelsWide * representation.pixelsHigh * 4)
            }
            images.setObject(image, forKey: url as NSURL, cost: cost)
        }
        return image
    }
}

private struct CachedAvatarImage: View {
    private struct LoadedImage {
        let url: URL
        let image: NSImage?
    }

    let url: URL?
    let borderColor: Color
    @State private var loaded: LoadedImage?

    var body: some View {
        let cachedImage = url.flatMap { AvatarImageCache.shared.cachedImage(for: $0) }
        let displayedImage = loaded?.url == url ? loaded?.image ?? cachedImage : cachedImage

        Group {
            if let displayedImage {
                Image(nsImage: displayedImage)
                    .resizable()
                    .scaledToFill()
                    .background(.background, in: Circle())
                    .clipShape(Circle())
                    .overlay(Circle().stroke(borderColor, lineWidth: 1))
            } else {
                Circle()
                    .fill(borderColor)
                    .frame(width: 6, height: 6)
            }
        }
        .frame(width: 14, height: 14)
        .task(id: url) {
            guard let url else {
                loaded = nil
                return
            }
            let image = await AvatarImageCache.shared.image(for: url)
            guard !Task.isCancelled else { return }
            loaded = LoadedImage(url: url, image: image)
        }
    }
}

private struct CommitAvatar: View {
    @Environment(RepositoryStore.self) private var repository
    let commit: Commit
    let borderColor: Color
    @State private var resolvedAvatarURL: URL?

    var body: some View {
        CachedAvatarImage(url: resolvedAvatarURL ?? fallbackAvatarURL, borderColor: borderColor)
        .task(id: "\(repository.githubRepository ?? ""):\(commit.id)") {
            resolvedAvatarURL = nil
            guard githubNoreplyAvatarURL == nil, let slug = repository.githubRepository else { return }
            let avatarURL = await GitHubAvatarResolver.shared.avatarURL(
                repository: slug,
                commit: commit.id
            )
            guard !Task.isCancelled else { return }
            resolvedAvatarURL = avatarURL
        }
    }

    private var fallbackAvatarURL: URL? {
        if let githubNoreplyAvatarURL { return githubNoreplyAvatarURL }
        let email = commit.authorEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !email.isEmpty else { return nil }
        let digest = Insecure.MD5.hash(data: Data(email.utf8)).map { String(format: "%02x", $0) }.joined()
        return URL(string: "https://www.gravatar.com/avatar/\(digest)?d=404&s=48")
    }

    private var githubNoreplyAvatarURL: URL? {
        let email = commit.authorEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if email.hasSuffix("@users.noreply.github.com") {
            let local = email.split(separator: "@", maxSplits: 1).first.map(String.init) ?? ""
            let username = local.split(separator: "+").last.map(String.init) ?? local
            if !username.isEmpty { return URL(string: "https://github.com/\(username).png?size=48") }
        }
        return nil
    }
}

private let commitGraphColors: [Color] = [
    .blue, .purple, .orange, .green, .pink, .cyan, .indigo, .mint
]

private struct CommitGraphLane: Equatable {
    let commitID: String
    let colorIndex: Int
}

private struct CommitGraphRow: Identifiable {
    let commit: Commit
    let topLanes: [CommitGraphLane]
    let bottomLanes: [CommitGraphLane]
    let nodeLane: Int
    var id: String { commit.id }
}

@MainActor
private final class CommitGraphRowsCache {
    private var commits: [Commit] = []
    private var cachedRows: [CommitGraphRow] = []

    func rows(for commits: [Commit]) -> [CommitGraphRow] {
        guard commits != self.commits else { return cachedRows }
        self.commits = commits
        cachedRows = commitGraphRows(commits)
        return cachedRows
    }
}

private func commitGraphRows(_ commits: [Commit]) -> [CommitGraphRow] {
    var lanes: [CommitGraphLane] = []
    var nextColorIndex = 0

    func takeColor(used: Set<Int>) -> Int {
        for offset in 0..<commitGraphColors.count {
            let candidate = (nextColorIndex + offset) % commitGraphColors.count
            if !used.contains(candidate) {
                nextColorIndex = (candidate + 1) % commitGraphColors.count
                return candidate
            }
        }
        let candidate = nextColorIndex % commitGraphColors.count
        nextColorIndex = (nextColorIndex + 1) % commitGraphColors.count
        return candidate
    }

    return commits.map { commit in
        if !lanes.contains(where: { $0.commitID == commit.id }) {
            lanes.insert(
                CommitGraphLane(
                    commitID: commit.id,
                    colorIndex: takeColor(used: Set(lanes.map(\.colorIndex)))
                ),
                at: 0
            )
        }
        let top = lanes
        let nodeLane = lanes.firstIndex(where: { $0.commitID == commit.id }) ?? 0
        let node = lanes.remove(at: nodeLane)
        var parentLanes: [CommitGraphLane] = []

        for (index, parent) in commit.parents.enumerated() {
            if let existingIndex = lanes.firstIndex(where: { $0.commitID == parent }) {
                parentLanes.append(lanes.remove(at: existingIndex))
            } else if index == 0 {
                parentLanes.append(CommitGraphLane(commitID: parent, colorIndex: node.colorIndex))
            } else {
                let used = Set((lanes + parentLanes).map(\.colorIndex))
                parentLanes.append(
                    CommitGraphLane(commitID: parent, colorIndex: takeColor(used: used))
                )
            }
        }

        lanes.insert(contentsOf: parentLanes, at: min(nodeLane, lanes.count))
        return CommitGraphRow(commit: commit, topLanes: top, bottomLanes: lanes, nodeLane: nodeLane)
    }
}

private struct StashGraphNode: View {
    let size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color.purple.opacity(0.16))
            .overlay {
                RoundedRectangle(cornerRadius: 2)
                    .stroke(
                        Color.purple,
                        style: StrokeStyle(lineWidth: 1.2, lineCap: .round, dash: [2, 2])
                    )
            }
            .overlay {
                if size >= 11 {
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(Color.purple)
                }
            }
            .frame(width: size, height: size)
    }
}

private struct CommitGraph: View {
    let row: CommitGraphRow
    let spacing: CGFloat
    let width: CGFloat
    let hidesConnections: Bool

    var body: some View {
        let displayedNodeLane = hidesConnections ? 0 : row.nodeLane
        let nodeColorIndex = row.topLanes.indices.contains(row.nodeLane)
            ? row.topLanes[row.nodeLane].colorIndex
            : 0
        let nodeColor = color(nodeColorIndex)

        ZStack(alignment: .topLeading) {
            Canvas { context, size in
                let centerY = size.height / 2
                let stroke = StrokeStyle(
                    lineWidth: max(1.1, min(1.5, spacing / 8)),
                    lineCap: .round,
                    lineJoin: .round
                )
                let commitStroke = row.commit.isStash
                    ? StrokeStyle(lineWidth: 1.25, lineCap: .round, lineJoin: .round, dash: [2, 2])
                    : stroke

                if !hidesConnections {
                    for (topLane, lane) in row.topLanes.enumerated() where lane.commitID != row.commit.id {
                        guard let bottomLane = row.bottomLanes.firstIndex(where: { $0.commitID == lane.commitID }) else {
                            continue
                        }
                        var path = Path()
                        path.move(to: point(topLane, -1))
                        path.addCurve(
                            to: point(bottomLane, size.height + 1),
                            control1: point(topLane, size.height * 0.38),
                            control2: point(bottomLane, size.height * 0.62)
                        )
                        context.stroke(
                            path,
                            with: .color(color(lane.colorIndex).opacity(0.82)),
                            style: stroke
                        )
                    }

                    var incoming = Path()
                    incoming.move(to: point(row.nodeLane, -1))
                    incoming.addLine(to: point(row.nodeLane, centerY))
                    context.stroke(incoming, with: .color(nodeColor), style: commitStroke)

                    for parent in row.commit.parents {
                        guard let lane = row.bottomLanes.firstIndex(where: { $0.commitID == parent }) else {
                            continue
                        }
                        var path = Path()
                        path.move(to: point(row.nodeLane, centerY))
                        path.addCurve(
                            to: point(lane, size.height + 1),
                            control1: point(row.nodeLane, size.height * 0.58),
                            control2: point(lane, size.height * 0.78)
                        )
                        context.stroke(
                            path,
                            with: .color(color(row.bottomLanes[lane].colorIndex)),
                            style: commitStroke
                        )
                    }
                }

            }

            if row.commit.isStash {
                let nodeSize = 14.0
                StashGraphNode(size: nodeSize)
                    .offset(x: x(displayedNodeLane) - nodeSize / 2, y: (24 - nodeSize) / 2)
            } else {
                CommitAvatar(commit: row.commit, borderColor: nodeColor)
                    .offset(x: x(displayedNodeLane) - 7, y: 5)
            }
        }
        .frame(width: width)
        .frame(height: 24)
        .help(hidesConnections ? "Graph connections are hidden while filtering commits" : "")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.commit.isStash ? "Stash graph node" : "Commit graph node")
        .accessibilityValue(
            "Lane \(displayedNodeLane + 1), \(row.commit.parents.count) parent\(row.commit.parents.count == 1 ? "" : "s")"
        )
    }

    private func color(_ index: Int) -> Color {
        commitGraphColors[index % commitGraphColors.count]
    }

    private func x(_ lane: Int) -> CGFloat { CGFloat(lane) * spacing + 8 }
    private func point(_ lane: Int, _ y: CGFloat) -> CGPoint { CGPoint(x: x(lane), y: y) }
}
