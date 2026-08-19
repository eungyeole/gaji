using Rift.Windows;

if (args.Length != 1) throw new ArgumentException("Pass a Git repository path.");

var repository = new RepositoryViewModel();
repository.Open(args[0]);

if (repository.RepositoryName.Length == 0) throw new InvalidOperationException("Repository name is empty.");
if (repository.Branch.Length == 0) throw new InvalidOperationException("Branch is empty.");
if (repository.Commits.Count == 0) throw new InvalidOperationException("Commit history is empty.");

Console.WriteLine($"Verified {repository.RepositoryName} on {repository.Branch}: {repository.Commits.Count} commits");
