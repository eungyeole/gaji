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
        repository.git(&["config", "user.name", "Gaji Test"]);
        repository.git(&["config", "user.email", "gaji@example.invalid"]);
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
    gaji_core::stage(repository.path(), &["hello.txt"]).unwrap();
    let staged = gaji_core::diff_summary(repository.path(), true).unwrap();
    assert_eq!(staged[0].path, "hello.txt");
    assert_eq!(staged[0].additions, Some(1));

    let head = gaji_core::commit(repository.path(), "initial", false).unwrap();
    repository.write("hello.txt", "hello again\n");
    gaji_core::stage(repository.path(), &["hello.txt"]).unwrap();
    gaji_core::commit_with_options(
        repository.path(),
        "signed off",
        gaji_core::CommitOptions {
            signoff: true,
            ..Default::default()
        },
    )
    .unwrap();
    assert!(
        repository
            .git(&["log", "-1", "--format=%B"])
            .contains("Signed-off-by: Gaji Test")
    );
    repository.write("hello.txt", "discard this\n");
    repository.write("scratch.txt", "untracked\n");
    gaji_core::discard(repository.path(), &["hello.txt", "scratch.txt"]).unwrap();
    assert_eq!(
        fs::read_to_string(repository.path().join("hello.txt")).unwrap(),
        "hello again\n"
    );
    assert!(!repository.path().join("scratch.txt").exists());
    gaji_core::create_branch(repository.path(), "feature", &head, true).unwrap();
    let branches = gaji_core::branches(repository.path()).unwrap();
    assert_eq!(branches.len(), 2);
    assert!(
        branches
            .iter()
            .any(|branch| branch.name == "feature" && branch.is_current)
    );

    gaji_core::switch_branch(repository.path(), "main").unwrap();
    gaji_core::delete_branch(repository.path(), "feature", false).unwrap();
    assert_eq!(gaji_core::branches(repository.path()).unwrap().len(), 1);
}

#[test]
fn manages_stashes_tags_and_remotes() {
    let repository = Repository::new();
    repository.write("hello.txt", "one\n");
    gaji_core::stage(repository.path(), &["hello.txt"]).unwrap();
    gaji_core::commit(repository.path(), "initial", false).unwrap();

    repository.write("hello.txt", "two\n");
    repository.write("new.txt", "new\n");
    gaji_core::stash_push(repository.path(), "work", true).unwrap();
    let stashes = gaji_core::stashes(repository.path()).unwrap();
    assert_eq!(stashes.len(), 1);
    assert!(stashes[0].subject.contains("work"));
    let files = gaji_core::stash_files(repository.path(), 0).unwrap();
    assert!(files.iter().any(|file| file.path == "hello.txt"));
    assert!(
        files
            .iter()
            .any(|file| file.path == "new.txt" && file.status == "A")
    );
    assert!(
        gaji_core::stash_file_diff(repository.path(), 0, "hello.txt")
            .unwrap()
            .contains("+two")
    );
    assert!(
        gaji_core::stash_file_diff(repository.path(), 0, "new.txt")
            .unwrap()
            .contains("+new")
    );
    gaji_core::stash_apply(repository.path(), 0, true).unwrap();

    gaji_core::create_tag(repository.path(), "v0.1.0", "HEAD", Some("first release")).unwrap();
    assert_eq!(gaji_core::tags(repository.path()).unwrap(), ["v0.1.0"]);
    gaji_core::delete_tag(repository.path(), "v0.1.0").unwrap();

    gaji_core::add_remote(
        repository.path(),
        "origin",
        "https://example.invalid/gaji.git",
    )
    .unwrap();
    let remotes = gaji_core::remotes(repository.path()).unwrap();
    assert_eq!(remotes[0].name, "origin");
    assert_eq!(remotes[0].fetch_url, "https://example.invalid/gaji.git");
    gaji_core::remove_remote(repository.path(), "origin").unwrap();
    assert!(gaji_core::remotes(repository.path()).unwrap().is_empty());
}

#[test]
fn checks_out_a_remote_branch_with_its_upstream() {
    let repository = Repository::new();
    repository.write("hello.txt", "hello\n");
    gaji_core::stage(repository.path(), &["hello.txt"]).unwrap();
    gaji_core::commit(repository.path(), "initial", false).unwrap();
    repository.git(&["remote", "add", "origin", "."]);
    repository.git(&["fetch", "-q", "origin", "main:refs/remotes/origin/topic"]);

    gaji_core::create_branch(repository.path(), "topic", "origin/topic", true).unwrap();

    assert_eq!(repository.git(&["branch", "--show-current"]), "topic");
    assert_eq!(
        repository.git(&[
            "rev-parse",
            "--abbrev-ref",
            "--symbolic-full-name",
            "@{upstream}"
        ]),
        "origin/topic"
    );
}

#[test]
fn reads_history_blame_and_manages_worktrees() {
    let repository = Repository::new();
    repository.write("hello.txt", "first\n");
    gaji_core::stage(repository.path(), &["hello.txt"]).unwrap();
    let head = gaji_core::commit(repository.path(), "initial", false).unwrap();
    repository.write("hello.txt", "first\nsecond\n");
    gaji_core::stage(repository.path(), &["hello.txt"]).unwrap();
    gaji_core::commit(repository.path(), "second line", false).unwrap();

    let history = gaji_core::file_history(repository.path(), "hello.txt").unwrap();
    assert_eq!(history.len(), 2);
    assert_eq!(history[0].subject, "second line");
    let graph = gaji_core::commit_graph(repository.path(), 100).unwrap();
    assert_eq!(graph.len(), 2);
    assert_eq!(graph[0].parents, [graph[1].id.clone()]);
    let files = gaji_core::commit_files(repository.path(), &graph[0].id).unwrap();
    assert_eq!(files[0].path, "hello.txt");
    assert!(
        gaji_core::commit_file_diff(repository.path(), &graph[0].id, "hello.txt")
            .unwrap()
            .contains("+second")
    );
    let blame = gaji_core::blame(repository.path(), "hello.txt").unwrap();
    assert_eq!(blame.len(), 2);
    assert_eq!(blame[1].content, "second");

    gaji_core::create_branch(repository.path(), "worktree-branch", &head, false).unwrap();
    let destination_parent = tempfile::tempdir().unwrap();
    let destination = destination_parent.path().join("feature-copy");
    gaji_core::add_worktree(repository.path(), &destination, "worktree-branch").unwrap();
    let worktrees = gaji_core::worktrees(repository.path()).unwrap();
    assert_eq!(worktrees.len(), 2);
    assert!(
        worktrees
            .iter()
            .any(|worktree| worktree.branch.as_deref() == Some("worktree-branch"))
    );
    gaji_core::remove_worktree(repository.path(), &destination, false).unwrap();
}

#[test]
fn classifies_graph_references_and_suppresses_tracking_aliases() {
    let repository = Repository::new();
    repository.write("hello.txt", "hello\n");
    gaji_core::stage(repository.path(), &["hello.txt"]).unwrap();
    let head = gaji_core::commit(repository.path(), "initial", false).unwrap();
    let long_branch = "feature/a-very-long-branch-name-that-must-remain-complete";
    let comma_branch = "topic,with-comma";
    repository.git(&["branch", long_branch]);
    repository.git(&["branch", comma_branch]);
    repository.git(&["branch", "local-follower"]);
    repository.git(&["config", "branch.local-follower.remote", "."]);
    repository.git(&["config", "branch.local-follower.merge", "refs/heads/main"]);
    gaji_core::create_tag(repository.path(), "v1.0.0", "HEAD", Some("release")).unwrap();
    repository.git(&["remote", "add", "origin", "."]);
    repository.git(&["fetch", "-q", "origin", "main:refs/remotes/origin/main"]);
    repository.git(&["branch", "--set-upstream-to", "origin/main", "main"]);
    repository.git(&[
        "symbolic-ref",
        "refs/remotes/origin/HEAD",
        "refs/remotes/origin/main",
    ]);

    let graph = gaji_core::commit_graph(repository.path(), 100).unwrap();
    let commit = graph.iter().find(|commit| commit.id == head).unwrap();

    assert!(commit.references.contains(&"HEAD -> main".to_owned()));
    assert!(commit.references.contains(&long_branch.to_owned()));
    assert!(commit.references.contains(&comma_branch.to_owned()));
    assert!(commit.references.contains(&"local-follower".to_owned()));
    assert!(commit.references.contains(&"tag: v1.0.0".to_owned()));
    assert!(!commit.references.contains(&"origin/main".to_owned()));
    assert!(!commit.references.contains(&"origin/HEAD".to_owned()));

    let local = commit
        .reference_details
        .iter()
        .find(|reference| reference.full_name == "refs/heads/main")
        .unwrap();
    assert_eq!(local.kind, gaji_core::GraphReferenceKind::LocalBranch);
    assert!(local.is_current);
    assert!(!local.is_suppressed);

    let tracking = commit
        .reference_details
        .iter()
        .find(|reference| reference.full_name == "refs/remotes/origin/main")
        .unwrap();
    assert_eq!(tracking.kind, gaji_core::GraphReferenceKind::RemoteBranch);
    assert!(tracking.is_suppressed);
    assert!(
        commit
            .reference_details
            .iter()
            .any(|reference| reference.name == long_branch)
    );
    assert!(
        commit
            .reference_details
            .iter()
            .any(|reference| reference.name == comma_branch)
    );
}

#[test]
fn identifies_stashes_and_hides_their_synthetic_helper_commits() {
    let repository = Repository::new();
    repository.write("hello.txt", "one\n");
    gaji_core::stage(repository.path(), &["hello.txt"]).unwrap();
    let base = gaji_core::commit(repository.path(), "initial", false).unwrap();
    repository.write("hello.txt", "two\n");
    repository.write("new.txt", "untracked\n");
    gaji_core::stash_push(repository.path(), "work", true).unwrap();

    let stash = repository.git(&["rev-parse", "refs/stash"]);
    let index_snapshot = repository.git(&["rev-parse", "refs/stash^2"]);
    let untracked_snapshot = repository.git(&["rev-parse", "refs/stash^3"]);
    let graph = gaji_core::commit_graph(repository.path(), 100).unwrap();
    let stash_commit = graph.iter().find(|commit| commit.id == stash).unwrap();

    assert_eq!(stash_commit.kind, gaji_core::GraphCommitKind::Stash);
    assert!(stash_commit.is_stash);
    assert_eq!(stash_commit.parents, [base]);
    assert_eq!(stash_commit.references, ["refs/stash"]);
    assert!(stash_commit.reference_details.iter().any(|reference| {
        reference.kind == gaji_core::GraphReferenceKind::Stash
            && reference.full_name == "refs/stash"
    }));
    assert!(!graph.iter().any(|commit| commit.id == index_snapshot));
    assert!(!graph.iter().any(|commit| commit.id == untracked_snapshot));
    assert!(
        graph
            .iter()
            .filter(|commit| commit.kind == gaji_core::GraphCommitKind::Commit)
            .all(|commit| !commit.is_stash)
    );
}

#[test]
fn returns_an_empty_graph_for_an_unborn_repository() {
    let repository = Repository::new();

    assert!(
        gaji_core::commit_graph(repository.path(), 100)
            .unwrap()
            .is_empty()
    );
}

#[test]
fn applies_hunks_and_clones_repositories() {
    let repository = Repository::new();
    repository.write("hello.txt", "first\n");
    gaji_core::stage(repository.path(), &["hello.txt"]).unwrap();
    gaji_core::commit(repository.path(), "initial searchable subject", false).unwrap();
    repository.write("hello.txt", "first\nsecond\n");

    let patch = gaji_core::file_diff(repository.path(), "hello.txt", false).unwrap();
    gaji_core::apply_diff_patch(repository.path(), &patch, true, false).unwrap();
    assert_eq!(
        gaji_core::diff_summary(repository.path(), true).unwrap()[0].additions,
        Some(1)
    );
    gaji_core::apply_diff_patch(repository.path(), &patch, true, true).unwrap();
    assert!(
        gaji_core::diff_summary(repository.path(), true)
            .unwrap()
            .is_empty()
    );
    assert_eq!(
        gaji_core::search_history(repository.path(), "searchable")
            .unwrap()
            .len(),
        1
    );

    let parent = tempfile::tempdir().unwrap();
    let clone_path = parent.path().join("clone");
    gaji_core::clone_repository(
        repository.path().to_string_lossy().as_ref(),
        &clone_path,
        false,
    )
    .unwrap();
    assert_eq!(gaji_core::branches(&clone_path).unwrap()[0].name, "main");

    let initialized = parent.path().join("initialized");
    gaji_core::initialize_repository(&initialized, "trunk").unwrap();
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
    gaji_core::stage(repository.path(), &["many.txt"]).unwrap();
    gaji_core::commit(repository.path(), "many lines", false).unwrap();

    let changed = original
        .replace("line 2\n", "changed 2\n")
        .replace("line 19\n", "changed 19\n");
    repository.write("many.txt", &changed);
    let details = gaji_core::file_diff_details(repository.path(), "many.txt", false).unwrap();
    assert!(details.patch.contains("changed 2"));
    let hunks = details.hunks;
    assert_eq!(hunks.len(), 2);
    gaji_core::apply_diff_patch(repository.path(), &hunks[0].patch, true, false).unwrap();
    let staged = gaji_core::file_diff(repository.path(), "many.txt", true).unwrap();
    assert!(staged.contains("changed 2"));
    assert!(!staged.contains("changed 19"));
}
