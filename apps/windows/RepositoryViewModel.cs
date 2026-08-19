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

    public ObservableCollection<CommitItem> Commits { get; } = [];
    public ObservableCollection<FileChangeItem> Changes { get; } = [];
    public string RepositoryName { get => repositoryName; private set => Set(ref repositoryName, value); }
    public string Branch { get => branch; private set => Set(ref branch, value); }
    public string DetailTitle { get => detailTitle; private set => Set(ref detailTitle, value); }
    public string DetailText { get => detailText; private set => Set(ref detailText, value); }
    public string CommitMessage { get => commitMessage; set => Set(ref commitMessage, value); }
    public Microsoft.UI.Xaml.Controls.InfoBadge ChangeBadge => new() { Value = Changes.Count };

    public event PropertyChangedEventHandler? PropertyChanged;

    public void Open(string path)
    {
        root = Git(path, "rev-parse", "--show-toplevel").Trim();
        RepositoryName = Path.GetFileName(root);
        Refresh();
    }

    public void Refresh()
    {
        if (root is null) return;
        try
        {
            Branch = Git(root, "branch", "--show-current").Trim();
            Changes.Clear();
            foreach (var line in Git(root, "status", "--porcelain=v1").Split('\n', StringSplitOptions.RemoveEmptyEntries))
                if (line.Length >= 4) Changes.Add(new(line[0], line[1], line[3..]));

            Commits.Clear();
            var log = TryGit(root, "log", "-n", "200", "--pretty=format:%H%x1f%an%x1f%s%x1e");
            foreach (var record in log.Split('\x1e', StringSplitOptions.RemoveEmptyEntries))
            {
                var fields = record.Trim().Split('\x1f', 3);
                if (fields.Length == 3) Commits.Add(new(fields[0], fields[1], fields[2]));
            }
            OnPropertyChanged(nameof(ChangeBadge));
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
        DetailTitle = commit.Subject;
        DetailText = TryGit(root, "show", "--stat", "--patch", "--no-ext-diff", commit.Id);
    }

    public void Commit()
    {
        if (root is null || string.IsNullOrWhiteSpace(CommitMessage)) return;
        Run("commit", "-m", CommitMessage.Trim());
        CommitMessage = "";
    }

    public void Run(params string[] arguments)
    {
        if (root is null) return;
        try { Git(root, arguments); }
        catch (Exception error) { DetailTitle = "Git error"; DetailText = error.Message; }
        Refresh();
    }

    private static string TryGit(string path, params string[] arguments)
    {
        try { return Git(path, arguments); } catch { return ""; }
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

public sealed record CommitItem(string Id, string Author, string Subject)
{
    public string ShortId => Id[..Math.Min(8, Id.Length)];
}

public sealed record FileChangeItem(char IndexStatus, char WorktreeStatus, string Path);
