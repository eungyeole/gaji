using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Windows.Storage.Pickers;
using WinRT.Interop;

namespace Rift.Windows;

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

    private void Refresh_Click(object sender, RoutedEventArgs e) => ViewModel.Refresh();
    private void Fetch_Click(object sender, RoutedEventArgs e) => ViewModel.Run("fetch", "--prune");
    private void Pull_Click(object sender, RoutedEventArgs e) => ViewModel.Run("pull", "--rebase");
    private void Push_Click(object sender, RoutedEventArgs e) => ViewModel.Run("push");
    private void Commit_Click(object sender, RoutedEventArgs e) => ViewModel.Commit();

    private void Commit_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if ((sender as ListView)?.SelectedItem is CommitItem commit) ViewModel.Select(commit);
    }
}
