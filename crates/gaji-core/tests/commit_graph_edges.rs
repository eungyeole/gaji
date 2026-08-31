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
        let output = Command::new("git")
            .args(["-C", self.path().to_string_lossy().as_ref()])
            .args(arguments)
            .output()
            .unwrap();
        assert!(
            output.status.success(),
            "git {arguments:?}: {}",
            String::from_utf8_lossy(&output.stderr)
        );
        String::from_utf8(output.stdout).unwrap().trim().to_owned()
    }

    fn commit_file(&self, path: &str, contents: &str, subject: &str) -> String {
        fs::write(self.path().join(path), contents).unwrap();
        self.git(&["add", "--", path]);
        self.git(&["commit", "-q", "-m", subject]);
        self.git(&["rev-parse", "HEAD"])
    }
}

#[test]
fn suppresses_only_an_exact_tracking_remote_alias() {
    let repository = Repository::new();
    let base = repository.commit_file("base.txt", "base\n", "base");
    repository.git(&["remote", "add", "origin", "."]);

    repository.git(&["branch", "exact", &base]);
    repository.git(&["update-ref", "refs/remotes/origin/exact", &base]);
    repository.git(&["branch", "--set-upstream-to", "origin/exact", "exact"]);

    repository.git(&["branch", "unrelated", &base]);
    repository.git(&["update-ref", "refs/remotes/origin/unrelated", &base]);

    repository.git(&["branch", "behind", &base]);
    repository.git(&["update-ref", "refs/remotes/origin/behind", &base]);
    repository.git(&["branch", "--set-upstream-to", "origin/behind", "behind"]);
    let remote_tip = repository.commit_file("remote.txt", "remote\n", "remote tip");
    repository.git(&["update-ref", "refs/remotes/origin/behind", &remote_tip]);
    repository.git(&["reset", "--hard", &base]);

    let graph = gaji_core::commit_graph(repository.path(), 100).unwrap();
    let base_commit = graph.iter().find(|commit| commit.id == base).unwrap();
    let remote_commit = graph.iter().find(|commit| commit.id == remote_tip).unwrap();

    let exact = base_commit
        .reference_details
        .iter()
        .find(|reference| reference.full_name == "refs/remotes/origin/exact")
        .unwrap();
    assert!(exact.is_suppressed);
    assert!(!base_commit.references.contains(&"origin/exact".to_owned()));

    let unrelated = base_commit
        .reference_details
        .iter()
        .find(|reference| reference.full_name == "refs/remotes/origin/unrelated")
        .unwrap();
    assert!(!unrelated.is_suppressed);
    assert!(
        base_commit
            .references
            .contains(&"origin/unrelated".to_owned())
    );

    let behind = remote_commit
        .reference_details
        .iter()
        .find(|reference| reference.full_name == "refs/remotes/origin/behind")
        .unwrap();
    assert!(!behind.is_suppressed);
    assert!(
        remote_commit
            .references
            .contains(&"origin/behind".to_owned())
    );
}

#[test]
fn preserves_requested_limit_after_hiding_stash_helpers() {
    let repository = Repository::new();
    for index in 0..4 {
        repository.commit_file(
            &format!("{index}.txt"),
            &format!("{index}\n"),
            &format!("commit {index}"),
        );
    }
    fs::write(repository.path().join("0.txt"), "changed\n").unwrap();
    fs::write(repository.path().join("untracked.txt"), "new\n").unwrap();
    gaji_core::stash_push(repository.path(), "edge", true).unwrap();

    let index_snapshot = repository.git(&["rev-parse", "refs/stash^2"]);
    let untracked_snapshot = repository.git(&["rev-parse", "refs/stash^3"]);
    assert_eq!(
        gaji_core::commit_graph(repository.path(), 0).unwrap().len(),
        1
    );
    for limit in 1..=5 {
        let graph = gaji_core::commit_graph(repository.path(), limit).unwrap();
        assert_eq!(graph.len(), limit);
        assert_eq!(
            graph,
            gaji_core::commit_graph_page(repository.path(), 0, limit).unwrap()
        );
        assert!(!graph.iter().any(|commit| commit.id == index_snapshot));
        assert!(!graph.iter().any(|commit| commit.id == untracked_snapshot));
    }
    assert_eq!(
        gaji_core::commit_graph(repository.path(), usize::MAX)
            .unwrap()
            .len(),
        5
    );
}

#[test]
fn paginated_graph_appends_without_duplicates_and_preserves_classification() {
    let repository = Repository::new();
    let commits: Vec<_> = (0..7)
        .map(|index| {
            repository.commit_file(
                &format!("{index}.txt"),
                &format!("{index}\n"),
                &format!("commit {index}"),
            )
        })
        .collect();
    repository.git(&["tag", "v1", &commits[1]]);
    repository.git(&["branch", "archive", &commits[1]]);

    fs::write(repository.path().join("6.txt"), "changed\n").unwrap();
    fs::write(repository.path().join("untracked.txt"), "new\n").unwrap();
    gaji_core::stash_push(repository.path(), "pagination", true).unwrap();
    let stash_id = repository.git(&["rev-parse", "refs/stash"]);
    let index_snapshot = repository.git(&["rev-parse", "refs/stash^2"]);
    let untracked_snapshot = repository.git(&["rev-parse", "refs/stash^3"]);

    let full = gaji_core::commit_graph(repository.path(), 100).unwrap();
    assert_eq!(full.len(), 8);

    let mut paged = Vec::new();
    for offset in (0..full.len()).step_by(2) {
        let page = gaji_core::commit_graph_page(repository.path(), offset, 2).unwrap();
        assert_eq!(page.len(), 2);
        paged.extend(page);
    }
    assert!(
        gaji_core::commit_graph_page(repository.path(), full.len(), 2)
            .unwrap()
            .is_empty()
    );

    assert_eq!(paged, full);
    let unique_ids: std::collections::HashSet<_> =
        paged.iter().map(|commit| commit.id.as_str()).collect();
    assert_eq!(unique_ids.len(), paged.len());
    assert!(!unique_ids.contains(index_snapshot.as_str()));
    assert!(!unique_ids.contains(untracked_snapshot.as_str()));

    let stash = paged.iter().find(|commit| commit.id == stash_id).unwrap();
    assert_eq!(stash.kind, gaji_core::GraphCommitKind::Stash);
    assert!(stash.is_stash);
    assert!(stash.reference_details.iter().any(|reference| {
        reference.full_name == "refs/stash"
            && reference.kind == gaji_core::GraphReferenceKind::Stash
    }));

    let decorated = paged.iter().find(|commit| commit.id == commits[1]).unwrap();
    assert!(decorated.reference_details.iter().any(|reference| {
        reference.full_name == "refs/tags/v1"
            && reference.kind == gaji_core::GraphReferenceKind::Tag
    }));
    assert!(decorated.reference_details.iter().any(|reference| {
        reference.full_name == "refs/heads/archive"
            && reference.kind == gaji_core::GraphReferenceKind::LocalBranch
    }));
}

#[test]
fn returns_clean_stash_references_with_stable_commit_ids() {
    let repository = Repository::new();
    repository.commit_file("tracked.txt", "one\n", "base");

    fs::write(repository.path().join("tracked.txt"), "two\n").unwrap();
    gaji_core::stash_push(repository.path(), "first", false).unwrap();
    fs::write(repository.path().join("tracked.txt"), "three\n").unwrap();
    gaji_core::stash_push(repository.path(), "second", false).unwrap();

    let stashes = gaji_core::stashes(repository.path()).unwrap();
    assert_eq!(stashes.len(), 2);
    assert_eq!(stashes[0].reference, "stash@{0}");
    assert_eq!(stashes[1].reference, "stash@{1}");
    assert_eq!(
        stashes[0].commit,
        repository.git(&["rev-parse", "stash@{0}"])
    );
    assert_eq!(
        stashes[1].commit,
        repository.git(&["rev-parse", "stash@{1}"])
    );
    assert!(stashes[0].subject.contains("second"));
    assert!(stashes[1].subject.contains("first"));
}

#[test]
fn includes_an_unreferenced_detached_head() {
    let repository = Repository::new();
    let base = repository.commit_file("base.txt", "base\n", "base");
    let detached = repository.commit_file("detached.txt", "detached\n", "detached");
    repository.git(&["checkout", "-q", "--detach", &detached]);
    repository.git(&["branch", "-D", "main"]);

    let graph = gaji_core::commit_graph(repository.path(), 100).unwrap();
    let head = graph.iter().find(|commit| commit.id == detached).unwrap();

    assert_eq!(head.references, ["HEAD"]);
    assert_eq!(head.parents, [base]);
    assert!(head.reference_details.iter().any(|reference| {
        reference.full_name == "HEAD"
            && reference.kind == gaji_core::GraphReferenceKind::Head
            && reference.is_current
    }));
}

#[test]
fn preserves_both_merge_parents() {
    let repository = Repository::new();
    let base = repository.commit_file("base.txt", "base\n", "base");
    repository.git(&["checkout", "-q", "-b", "topic"]);
    let topic = repository.commit_file("topic.txt", "topic\n", "topic");
    repository.git(&["checkout", "-q", "main"]);
    let main = repository.commit_file("main.txt", "main\n", "main");
    repository.git(&["merge", "-q", "--no-ff", "-m", "merge", "topic"]);
    let merge = repository.git(&["rev-parse", "HEAD"]);

    let graph = gaji_core::commit_graph(repository.path(), 100).unwrap();
    let merge_commit = graph.iter().find(|commit| commit.id == merge).unwrap();

    assert_eq!(merge_commit.parents, [main, topic]);
    assert!(graph.iter().any(|commit| commit.id == base));
}

#[test]
fn preserves_control_characters_in_commit_subjects() {
    let repository = Repository::new();
    let subject = "before\u{1e}middle\u{1f}after";
    let commit = repository.commit_file("control.txt", "control\n", subject);

    let graph = gaji_core::commit_graph(repository.path(), 100).unwrap();
    let entry = graph.iter().find(|entry| entry.id == commit).unwrap();

    assert_eq!(entry.subject, subject);
}
