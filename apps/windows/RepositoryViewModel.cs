using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.CompilerServices;

namespace Rift.Windows;

public sealed class RepositoryViewModel : INotifyPropertyChanged
{
    private string? root;
    private string repositoryName = "Rift";
    private string branch = "Open a repository";
    private string detailTitle = "Welcome to Rift";
    private string detailText = "Open a local Git repository to begin.";
    private string commitMessage = "";
    private string? operation;
    private FileChangeItem? selectedChange;
    private CommitItem? selectedCommit;
    private readonly List<CommitItem> allCommits = [];

    public ObservableCollection<CommitItem> Commits { get; } = [];
    public ObservableCollection<FileChangeItem> Changes { get; } = [];
    public ObservableCollection<string> Branches { get; } = [];
    public ObservableCollection<string> Tags { get; } = [];
    public string RepositoryName { get => repositoryName; private set => Set(ref repositoryName, value); }
    public string Branch { get => branch; private set => Set(ref branch, value); }
    public string DetailTitle { get => detailTitle; private set => Set(ref detailTitle, value); }
    public string DetailText { get => detailText; private set => Set(ref detailText, value); }
    public string CommitMessage { get => commitMessage; set => Set(ref commitMessage, value); }
    public int ChangeCount => Changes.Count;
    public bool HasOperation => operation is not null;
    public bool HasSelectedConflict => selectedChange?.IsConflict == true;
    public bool HasSelectedCommit => selectedCommit is not null;

    public event PropertyChangedEventHandler? PropertyChanged;

    public void Open(string path)
    {
        root = NativeCore.Inspect(path).Root;
        RepositoryName = Path.GetFileName(root);
        Refresh();
    }

    public void Initialize(string path)
    {
        NativeCore.Execute(new { action = "initialize", path, defaultBranch = "main" });
        Open(path);
    }

    public void Clone(string url, string destination)
    {
        NativeCore.Execute(new { action = "clone", url, destination, bare = false });
        Open(destination);
    }

    public void Refresh()
    {
        if (root is null) return;
        try
        {
            var snapshot = NativeCore.Inspect(root);
            Branch = snapshot.Branch;
            Branches.Clear();
            foreach (var name in Git(root, "branch", "--format=%(refname:short)").Split('\n', StringSplitOptions.RemoveEmptyEntries))
                Branches.Add(name);
            Tags.Clear();
            foreach (var tag in Git(root, "tag", "--list").Split('\n', StringSplitOptions.RemoveEmptyEntries))
                Tags.Add(tag);
            operation = DetectOperation(root);
            OnPropertyChanged(nameof(HasOperation));
            Changes.Clear();
            foreach (var change in snapshot.Changes)
                Changes.Add(new(
                    change.IndexStatus.Length == 0 ? ' ' : change.IndexStatus[0],
                    change.WorktreeStatus.Length == 0 ? ' ' : change.WorktreeStatus[0],
                    change.Path));

            Commits.Clear();
            allCommits.Clear();
            foreach (var commit in NativeCore.Graph(root))
                allCommits.Add(new(commit.Id, commit.Author, commit.Subject, commit.Parents, commit.References));
            foreach (var commit in allCommits) Commits.Add(commit);
            OnPropertyChanged(nameof(ChangeCount));
        }
        catch (Exception error)
        {
            DetailTitle = "Git error";
            DetailText = error.Message;
        }
    }

    public void Select(CommitItem commit)
    {
        if (root is null) return;
        selectedCommit = commit;
        OnPropertyChanged(nameof(HasSelectedCommit));
        DetailTitle = commit.Subject;
        DetailText = TryGit(root, "show", "--stat", "--patch", "--no-ext-diff", commit.Id);
    }

    public void Select(FileChangeItem change)
    {
        if (root is null) return;
        selectedChange = change;
        OnPropertyChanged(nameof(HasSelectedConflict));
        DetailTitle = change.Path;
        if (change.IsConflict)
        {
            var @base = TryGit(root, "show", $":1:{change.Path}");
            var ours = TryGit(root, "show", $":2:{change.Path}");
            var theirs = TryGit(root, "show", $":3:{change.Path}");
            DetailText = $"BASE\n────\n{@base}\n\nCURRENT\n───────\n{ours}\n\nINCOMING\n────────\n{theirs}";
        }
        else
        {
            var staged = change.IndexStatus is not ' ' and not '?';
            DetailText = staged
                ? TryGit(root, "diff", "--cached", "--", change.Path)
                : TryGit(root, "diff", "--no-ext-diff", "--", change.Path);
        }
    }

    public void ResolveSelected(string side)
    {
        if (selectedChange is null || root is null) return;
        RunNative(new {
            action = "resolve", path = root, file = selectedChange.Path,
            side = side == "--ours" ? "ours" : "theirs"
        });
        selectedChange = null;
        OnPropertyChanged(nameof(HasSelectedConflict));
    }

    public void Commit()
    {
        if (root is null || string.IsNullOrWhiteSpace(CommitMessage)) return;
        RunNative(new { action = "commit", path = root, message = CommitMessage.Trim(), amend = false });
        CommitMessage = "";
    }

    public void ContinueOperation()
    {
        if (operation is null || root is null) return;
        RunNative(new { action = "continue", path = root });
    }

    public void AbortOperation()
    {
        if (operation is null || root is null) return;
        RunNative(new { action = "abort", path = root });
    }

    public void StageAll()
    {
        if (root is null || Changes.Count == 0) return;
        RunNative(new { action = "stage", path = root, files = Changes.Select(change => change.Path).ToArray() });
    }

    public void UnstageAll()
    {
        if (root is null) return;
        var files = Changes
            .Where(change => change.IndexStatus is not ' ' and not '?')
            .Select(change => change.Path)
            .ToArray();
        if (files.Length > 0) RunNative(new { action = "unstage", path = root, files });
    }

    public void SwitchBranch(string branchName)
    {
        if (root is not null)
            RunNative(new { action = "switchBranch", path = root, branch = branchName });
    }

    public void Fetch()
    {
        if (root is null) return;
        var remote = FirstRemote();
        if (remote is not null) RunNative(new { action = "fetch", path = root, remote, prune = true });
    }

    public void Pull()
    {
        if (root is not null) RunNative(new { action = "pull", path = root, rebase = true });
    }

    public void Push()
    {
        if (root is null) return;
        var remote = FirstRemote();
        if (remote is not null) RunNative(new {
            action = "push", path = root, remote, branch = Branch,
            setUpstream = false, forceWithLease = false
        });
    }

    public void CreateTag(string name)
    {
        if (root is null || selectedCommit is null) return;
        RunNative(new { action = "createTag", path = root, name, target = selectedCommit.Id });
    }

    public void AddRemote(string name, string url)
    {
        if (root is not null) RunNative(new { action = "addRemote", path = root, name, url });
    }

    public void FilterCommits(string query)
    {
        var normalized = query.Trim();
        var matches = normalized.Length == 0 ? allCommits : allCommits.Where(commit =>
            commit.Subject.Contains(normalized, StringComparison.OrdinalIgnoreCase) ||
            commit.Author.Contains(normalized, StringComparison.OrdinalIgnoreCase) ||
            commit.Id.Contains(normalized, StringComparison.OrdinalIgnoreCase));
        Commits.Clear();
        foreach (var commit in matches) Commits.Add(commit);
    }

    private string? FirstRemote() => root is null
        ? null
        : Git(root, "remote").Split('\n', StringSplitOptions.RemoveEmptyEntries).FirstOrDefault();

    private void RunNative(object request)
    {
        try { NativeCore.Execute(request); }
        catch (Exception error) { DetailTitle = "Git error"; DetailText = error.Message; }
        Refresh();
    }

    private static string TryGit(string path, params string[] arguments)
    {
        try { return Git(path, arguments); } catch { return ""; }
    }

    private static string? DetectOperation(string path)
    {
        string GitPath(string name) => Git(path, "rev-parse", "--path-format=absolute", "--git-path", name).Trim();
        if (Directory.Exists(GitPath("rebase-merge")) || Directory.Exists(GitPath("rebase-apply"))) return "rebase";
        if (File.Exists(GitPath("CHERRY_PICK_HEAD"))) return "cherry-pick";
        if (File.Exists(GitPath("MERGE_HEAD"))) return "merge";
        if (File.Exists(GitPath("REVERT_HEAD"))) return "revert";
        return null;
    }

    private static string Git(string path, params string[] arguments)
    {
        var start = new ProcessStartInfo("git") {
            WorkingDirectory = path,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true
        };
        start.Environment["GIT_EDITOR"] = "true";
        start.ArgumentList.Add("-C");
        start.ArgumentList.Add(path);
        foreach (var argument in arguments) start.ArgumentList.Add(argument);
        using var process = Process.Start(start) ?? throw new InvalidOperationException("Git is not installed.");
        var output = process.StandardOutput.ReadToEnd();
        var error = process.StandardError.ReadToEnd();
        process.WaitForExit();
        if (process.ExitCode != 0) throw new InvalidOperationException(error.Trim());
        return output;
    }

    private void Set(ref string field, string value, [CallerMemberName] string? property = null)
    {
        if (field == value) return;
        field = value;
        OnPropertyChanged(property);
    }

    private void OnPropertyChanged([CallerMemberName] string? property = null) =>
        PropertyChanged?.Invoke(this, new(property));
}

public sealed record CommitItem(string Id, string Author, string Subject, string[] Parents, string[] References)
{
    public string ShortId => Id[..Math.Min(8, Id.Length)];
    public string RefLabel => string.Join(" · ", References);
}

public sealed record FileChangeItem(char IndexStatus, char WorktreeStatus, string Path)
{
    public string Status => IndexStatus == '?' ? "U" : (IndexStatus == ' ' ? WorktreeStatus : IndexStatus).ToString();
    public bool IsConflict => IndexStatus == 'U' || WorktreeStatus == 'U' || (IndexStatus == 'A' && WorktreeStatus == 'A') || (IndexStatus == 'D' && WorktreeStatus == 'D');
}
