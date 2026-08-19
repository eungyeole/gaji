import AppKit
import SwiftUI

struct ContentView: View {
    @Environment(RepositoryStore.self) private var repository

    var body: some View {
        @Bindable var repository = repository

        Group {
            if repository.root == nil {
                WelcomeView()
            } else {
                VStack(spacing: 0) {
                    if repository.operation != nil {
                        ConflictBar()
                        Divider()
                    }
                    NavigationSplitView {
                        SidebarView()
                            .navigationSplitViewColumnWidth(min: 190, ideal: 230, max: 300)
                    } content: {
                        CommitList(selection: $repository.selection)
                            .navigationSplitViewColumnWidth(min: 340, ideal: 430)
                    } detail: {
                        CommitDetail()
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
                Button(action: repository.chooseRepository) {
                    Label("Open Repository", systemImage: "folder")
                }
            }
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
                Text(repository.conflicts.isEmpty ? "Ready to continue" : "Resolve (repository.conflicts.count) conflict(s)")
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
                Button("Open Repository…", action: repository.chooseRepository)
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
            }
            .padding(42)
            .glassEffect(.regular, in: .rect(cornerRadius: 28))
        }
    }
}

private struct SidebarView: View {
    @Environment(RepositoryStore.self) private var repository

    var body: some View {
        List {
            Section("Repository") {
                Label(repository.branch.isEmpty ? "No commits yet" : repository.branch,
                      systemImage: "arrow.triangle.branch")
                Label("History", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
            }
            Section("Working Copy") {
                Label("Changes", systemImage: "square.and.pencil").badge(repository.changes.count)
                ForEach(repository.changes.prefix(20)) { change in
                    Label(change.path, systemImage: icon(for: change.statusLabel)).help(change.path)
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func icon(for status: String) -> String {
        switch status {
        case "A", "U": "plus.circle"
        case "D": "minus.circle"
        case "R": "arrow.right.circle"
        default: "pencil.circle"
        }
    }
}

private struct CommitList: View {
    @Environment(RepositoryStore.self) private var repository
    @Binding var selection: Commit.ID?

    var body: some View {
        List(repository.commits, selection: $selection) { commit in
            VStack(alignment: .leading, spacing: 5) {
                Text(commit.subject).fontWeight(.medium).lineLimit(2)
                HStack {
                    Text(commit.author)
                    Spacer()
                    if let date = commit.date { Text(date, style: .relative) }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 3)
            .contextMenu {
                Button("Cherry-Pick (String(commit.id.prefix(8)))") {
                    repository.cherryPick(commit)
                }
                .disabled(repository.operation != nil)
                Button("Copy Commit Hash") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(commit.id, forType: .string)
                }
            }
        }
        .overlay {
            if repository.commits.isEmpty {
                ContentUnavailableView("No Commits", systemImage: "clock",
                    description: Text("Create the first commit to begin this repository’s history."))
            }
        }
    }
}

private struct CommitDetail: View {
    @Environment(RepositoryStore.self) private var repository
    private var commit: Commit? { repository.commits.first { $0.id == repository.selection } }

    var body: some View {
        if let commit {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(commit.subject).font(.title2.bold())
                    LabeledContent("Author", value: commit.author)
                    LabeledContent("Commit", value: String(commit.id.prefix(12)))
                    if let date = commit.date { LabeledContent("Date") { Text(date, format: .dateTime) } }
                    Divider()
                    ContentUnavailableView("Diff Preview", systemImage: "doc.text.magnifyingglass",
                        description: Text("File and hunk rendering is the next vertical slice."))
                        .frame(maxWidth: .infinity, minHeight: 260)
                }
                .padding(24)
            }
        } else {
            ContentUnavailableView("Select a Commit", systemImage: "point.3.connected.trianglepath.dotted")
        }
    }
}
