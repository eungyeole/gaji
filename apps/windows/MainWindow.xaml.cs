using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Windows.Storage.Pickers;
using WinRT.Interop;

namespace Gaji.Windows;

public sealed partial class MainWindow : Window
{
    public RepositoryViewModel ViewModel { get; } = new();

    public MainWindow()
    {
        InitializeComponent();
        ExtendsContentIntoTitleBar = true;
    }

    private async void OpenRepository_Click(object sender, RoutedEventArgs e)
    {
        var picker = new FolderPicker();
        picker.FileTypeFilter.Add("*");
        InitializeWithWindow.Initialize(picker, WindowNative.GetWindowHandle(this));
        var folder = await picker.PickSingleFolderAsync();
        if (folder is not null) ViewModel.Open(folder.Path);
    }

    private async void NewRepository_Click(object sender, RoutedEventArgs e)
    {
        var folder = await PickFolder("Choose a folder for the new repository");
        if (folder is not null) ViewModel.Initialize(folder.Path);
    }

    private async void CloneRepository_Click(object sender, RoutedEventArgs e)
    {
        var urlBox = new TextBox { PlaceholderText = "https://github.com/owner/repository.git" };
        var dialog = new ContentDialog {
            XamlRoot = Content.XamlRoot,
            Title = "Clone Repository",
            Content = urlBox,
            PrimaryButtonText = "Next",
            CloseButtonText = "Cancel",
            DefaultButton = ContentDialogButton.Primary
        };
        if (await dialog.ShowAsync() != ContentDialogResult.Primary || string.IsNullOrWhiteSpace(urlBox.Text)) return;
        var parent = await PickFolder("Choose the destination folder");
        if (parent is null) return;
        var name = urlBox.Text.Trim().TrimEnd('/').Split('/').Last().Replace(".git", "");
        ViewModel.Clone(urlBox.Text.Trim(), Path.Combine(parent.Path, name));
    }

    private async Task<global::Windows.Storage.StorageFolder?> PickFolder(string title)
    {
        var picker = new FolderPicker { SuggestedStartLocation = PickerLocationId.ComputerFolder };
        picker.FileTypeFilter.Add("*");
        InitializeWithWindow.Initialize(picker, WindowNative.GetWindowHandle(this));
        return await picker.PickSingleFolderAsync();
    }

    private void Refresh_Click(object sender, RoutedEventArgs e) => ViewModel.Refresh();
    private void Fetch_Click(object sender, RoutedEventArgs e) => ViewModel.Fetch();
    private void Pull_Click(object sender, RoutedEventArgs e) => ViewModel.Pull();
    private void Push_Click(object sender, RoutedEventArgs e) => ViewModel.Push();
    private void StageAll_Click(object sender, RoutedEventArgs e) => ViewModel.StageAll();
    private void UnstageAll_Click(object sender, RoutedEventArgs e) => ViewModel.UnstageAll();
    private void Continue_Click(object sender, RoutedEventArgs e) => ViewModel.ContinueOperation();
    private void Abort_Click(object sender, RoutedEventArgs e) => ViewModel.AbortOperation();
    private void UseCurrent_Click(object sender, RoutedEventArgs e) => ViewModel.ResolveSelected("--ours");
    private void UseIncoming_Click(object sender, RoutedEventArgs e) => ViewModel.ResolveSelected("--theirs");
    private void Blame_Click(object sender, RoutedEventArgs e) => ViewModel.ShowBlame();
    private void UpdateSubmodules_Click(object sender, RoutedEventArgs e) => ViewModel.UpdateSubmodules();
    private void Stash_Click(object sender, RoutedEventArgs e) => ViewModel.StashAll();
    private void PopStash_Click(object sender, RoutedEventArgs e) => ViewModel.PopLatestStash();
    private void ApplyHunk_Click(object sender, RoutedEventArgs e) => ViewModel.ApplySelectedHunk();

    private async void AddWorktree_Click(object sender, RoutedEventArgs e)
    {
        var branches = new ComboBox { Header = "Branch", ItemsSource = ViewModel.Branches };
        var dialog = new ContentDialog {
            XamlRoot = Content.XamlRoot, Title = "Add Worktree", Content = branches,
            PrimaryButtonText = "Next", CloseButtonText = "Cancel"
        };
        if (await dialog.ShowAsync() != ContentDialogResult.Primary || branches.SelectedItem is not string branch) return;
        var parent = await PickFolder("Choose the worktree parent folder");
        if (parent is not null) ViewModel.AddWorktree(Path.Combine(parent.Path, branch), branch);
    }

    private async void RenameBranch_Click(object sender, RoutedEventArgs e)
    {
        var name = new TextBox { Text = ViewModel.Branch };
        var dialog = new ContentDialog {
            XamlRoot = Content.XamlRoot, Title = "Rename Branch", Content = name,
            PrimaryButtonText = "Rename", CloseButtonText = "Cancel"
        };
        if (await dialog.ShowAsync() == ContentDialogResult.Primary && !string.IsNullOrWhiteSpace(name.Text))
            ViewModel.RenameBranch(ViewModel.Branch, name.Text.Trim());
    }

    private async void NewBranch_Click(object sender, RoutedEventArgs e)
    {
        var name = new TextBox { PlaceholderText = "feature/my-change" };
        var dialog = new ContentDialog {
            XamlRoot = Content.XamlRoot, Title = "New Branch", Content = name,
            PrimaryButtonText = "Create and Switch", CloseButtonText = "Cancel"
        };
        if (await dialog.ShowAsync() == ContentDialogResult.Primary && !string.IsNullOrWhiteSpace(name.Text))
            ViewModel.CreateBranch(name.Text.Trim());
    }

    private async void DeleteBranch_Click(object sender, RoutedEventArgs e)
    {
        var branches = new ComboBox {
            Header = "Branch", ItemsSource = ViewModel.Branches.Where(branch => branch != ViewModel.Branch).ToArray()
        };
        var dialog = new ContentDialog {
            XamlRoot = Content.XamlRoot, Title = "Delete Merged Branch", Content = branches,
            PrimaryButtonText = "Delete", CloseButtonText = "Cancel"
        };
        if (await dialog.ShowAsync() == ContentDialogResult.Primary && branches.SelectedItem is string branch)
            ViewModel.DeleteBranch(branch);
    }

    private async void CreateTag_Click(object sender, RoutedEventArgs e)
    {
        var name = new TextBox { PlaceholderText = "v1.0.0" };
        var dialog = new ContentDialog {
            XamlRoot = Content.XamlRoot, Title = "Create Tag", Content = name,
            PrimaryButtonText = "Create", CloseButtonText = "Cancel"
        };
        if (await dialog.ShowAsync() == ContentDialogResult.Primary && !string.IsNullOrWhiteSpace(name.Text))
            ViewModel.CreateTag(name.Text.Trim());
    }

    private async void AddRemote_Click(object sender, RoutedEventArgs e)
    {
        var name = new TextBox { Header = "Name", Text = "origin" };
        var url = new TextBox { Header = "URL", PlaceholderText = "https://github.com/owner/repository.git" };
        var fields = new StackPanel { Spacing = 12 };
        fields.Children.Add(name);
        fields.Children.Add(url);
        var dialog = new ContentDialog {
            XamlRoot = Content.XamlRoot, Title = "Add Remote", Content = fields,
            PrimaryButtonText = "Add", CloseButtonText = "Cancel"
        };
        if (await dialog.ShowAsync() == ContentDialogResult.Primary &&
            !string.IsNullOrWhiteSpace(name.Text) && !string.IsNullOrWhiteSpace(url.Text))
            ViewModel.AddRemote(name.Text.Trim(), url.Text.Trim());
    }
    private void Commit_Click(object sender, RoutedEventArgs e) => ViewModel.Commit();

    private void Commit_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if ((sender as ListView)?.SelectedItem is CommitItem commit) ViewModel.Select(commit);
    }

    private void Change_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if ((sender as ListView)?.SelectedItem is FileChangeItem change) ViewModel.Select(change);
    }

    private void Branch_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if ((sender as ComboBox)?.SelectedItem is string branch && branch != ViewModel.Branch)
            ViewModel.SwitchBranch(branch);
    }

    private void Search_TextChanged(AutoSuggestBox sender, AutoSuggestBoxTextChangedEventArgs args) =>
        ViewModel.FilterCommits(sender.Text);

    private void RecentRepository_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if ((sender as ListView)?.SelectedItem is string path) ViewModel.Open(path);
    }
}
