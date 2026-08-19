use std::fs;
use std::path::Path;
use std::process::Command;

use tempfile::TempDir;

struct Repository {
    directory: TempDir,
}

impl Repository {
    fn new() -> Self {
        let repository = Self {
            directory: tempfile::tempdir().unwrap(),
        };
        repository.git(&["init", "-q", "-b", "main"]);
        repository.git(&["config", "user.name", "Rift Test"]);
        repository.git(&["config", "user.email", "rift@example.invalid"]);
        repository
    }

    fn path(&self) -> &Path {
        self.directory.path()
    }

    fn git(&self, arguments: &[&str]) -> String {
        Self::git_at(self.path(), arguments)
    }

    fn git_at(path: &Path, arguments: &[&str]) -> String {
        let output = Command::new("git")
            .args(["-C", path.to_string_lossy().as_ref()])
            .args(arguments)
            .output()
            .unwrap();
        assert!(
            output.status.success(),
            "{}",
            String::from_utf8_lossy(&output.stderr)
        );
        String::from_utf8(output.stdout).unwrap().trim().to_owned()
    }

    fn write(&self, path: &str, contents: &str) {
        fs::write(self.path().join(path), contents).unwrap();
    }
}

#[test]
fn stages_diffs_commits_and_manages_branches() {
    let repository = Repository::new();
    repository.write("hello.txt", "hello\n");
    rift_core::stage(repository.path(), &["hello.txt"]).unwrap();
    let staged = rift_core::diff_summary(repository.path(), true).unwrap();
    assert_eq!(staged[0].path, "hello.txt");
    assert_eq!(staged[0].additions, Some(1));

    let head = rift_core::commit(repository.path(), "initial", false).unwrap();
    rift_core::create_branch(repository.path(), "feature", &head, true).unwrap();
    let branches = rift_core::branches(repository.path()).unwrap();
    assert_eq!(branches.len(), 2);
    assert!(
        branches
            .iter()
            .any(|branch| branch.name == "feature" && branch.is_current)
    );

    rift_core::switch_branch(repository.path(), "main").unwrap();
    rift_core::delete_branch(repository.path(), "feature", false).unwrap();
    assert_eq!(rift_core::branches(repository.path()).unwrap().len(), 1);
}

#[test]
fn manages_stashes_tags_and_remotes() {
    let repository = Repository::new();
    repository.write("hello.txt", "one\n");
    rift_core::stage(repository.path(), &["hello.txt"]).unwrap();
    rift_core::commit(repository.path(), "initial", false).unwrap();

    repository.write("hello.txt", "two\n");
    rift_core::stash_push(repository.path(), "work", false).unwrap();
    let stashes = rift_core::stashes(repository.path()).unwrap();
    assert_eq!(stashes.len(), 1);
    assert!(stashes[0].subject.contains("work"));
    rift_core::stash_apply(repository.path(), 0, true).unwrap();

    rift_core::create_tag(repository.path(), "v0.1.0", "HEAD", Some("first release")).unwrap();
    assert_eq!(rift_core::tags(repository.path()).unwrap(), ["v0.1.0"]);
    rift_core::delete_tag(repository.path(), "v0.1.0").unwrap();

    rift_core::add_remote(
        repository.path(),
        "origin",
        "https://example.invalid/rift.git",
    )
    .unwrap();
    let remotes = rift_core::remotes(repository.path()).unwrap();
    assert_eq!(remotes[0].name, "origin");
    assert_eq!(remotes[0].fetch_url, "https://example.invalid/rift.git");
    rift_core::remove_remote(repository.path(), "origin").unwrap();
    assert!(rift_core::remotes(repository.path()).unwrap().is_empty());
}

#[test]
fn reads_history_blame_and_manages_worktrees() {
    let repository = Repository::new();
    repository.write("hello.txt", "first\n");
    rift_core::stage(repository.path(), &["hello.txt"]).unwrap();
    let head = rift_core::commit(repository.path(), "initial", false).unwrap();
    repository.write("hello.txt", "first\nsecond\n");
    rift_core::stage(repository.path(), &["hello.txt"]).unwrap();
    rift_core::commit(repository.path(), "second line", false).unwrap();

    let history = rift_core::file_history(repository.path(), "hello.txt").unwrap();
    assert_eq!(history.len(), 2);
    assert_eq!(history[0].subject, "second line");
    let graph = rift_core::commit_graph(repository.path(), 100).unwrap();
    assert_eq!(graph.len(), 2);
    assert_eq!(graph[0].parents, [graph[1].id.clone()]);
    let blame = rift_core::blame(repository.path(), "hello.txt").unwrap();
    assert_eq!(blame.len(), 2);
    assert_eq!(blame[1].content, "second");

    rift_core::create_branch(repository.path(), "worktree-branch", &head, false).unwrap();
    let destination_parent = tempfile::tempdir().unwrap();
    let destination = destination_parent.path().join("feature-copy");
    rift_core::add_worktree(repository.path(), &destination, "worktree-branch").unwrap();
    let worktrees = rift_core::worktrees(repository.path()).unwrap();
    assert_eq!(worktrees.len(), 2);
    assert!(
        worktrees
            .iter()
            .any(|worktree| worktree.branch.as_deref() == Some("worktree-branch"))
    );
    rift_core::remove_worktree(repository.path(), &destination, false).unwrap();
}

#[test]
fn applies_hunks_and_clones_repositories() {
    let repository = Repository::new();
    repository.write("hello.txt", "first\n");
    rift_core::stage(repository.path(), &["hello.txt"]).unwrap();
    rift_core::commit(repository.path(), "initial searchable subject", false).unwrap();
    repository.write("hello.txt", "first\nsecond\n");

    let patch = rift_core::file_diff(repository.path(), "hello.txt", false).unwrap();
    rift_core::apply_diff_patch(repository.path(), &patch, true, false).unwrap();
    assert_eq!(
        rift_core::diff_summary(repository.path(), true).unwrap()[0].additions,
        Some(1)
    );
    rift_core::apply_diff_patch(repository.path(), &patch, true, true).unwrap();
    assert!(
        rift_core::diff_summary(repository.path(), true)
            .unwrap()
            .is_empty()
    );
    assert_eq!(
        rift_core::search_history(repository.path(), "searchable")
            .unwrap()
            .len(),
        1
    );

    let parent = tempfile::tempdir().unwrap();
    let clone_path = parent.path().join("clone");
    rift_core::clone_repository(
        repository.path().to_string_lossy().as_ref(),
        &clone_path,
        false,
    )
    .unwrap();
    assert_eq!(rift_core::branches(&clone_path).unwrap()[0].name, "main");

    let initialized = parent.path().join("initialized");
    rift_core::initialize_repository(&initialized, "trunk").unwrap();
    assert_eq!(
        Repository::git_at(&initialized, &["branch", "--show-current"]),
        "trunk"
    );
}

#[test]
fn splits_and_stages_individual_hunks() {
    let repository = Repository::new();
    let original = (1..=20)
        .map(|line| format!("line {line}\n"))
        .collect::<String>();
    repository.write("many.txt", &original);
    rift_core::stage(repository.path(), &["many.txt"]).unwrap();
    rift_core::commit(repository.path(), "many lines", false).unwrap();

    let changed = original
        .replace("line 2\n", "changed 2\n")
        .replace("line 19\n", "changed 19\n");
    repository.write("many.txt", &changed);
    let hunks = rift_core::file_hunks(repository.path(), "many.txt", false).unwrap();
    assert_eq!(hunks.len(), 2);
    rift_core::apply_diff_patch(repository.path(), &hunks[0].patch, true, false).unwrap();
    let staged = rift_core::file_diff(repository.path(), "many.txt", true).unwrap();
    assert!(staged.contains("changed 2"));
    assert!(!staged.contains("changed 19"));
}
