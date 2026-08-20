use std::fs;
use std::path::Path;
use std::process::Command;

use gaji_core::{ConflictSide, OperationKind};
use tempfile::TempDir;

struct TestRepository {
    directory: TempDir,
}

impl TestRepository {
    fn new() -> Self {
        let repository = Self {
            directory: tempfile::tempdir().expect("create temporary repository"),
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
            .env("GIT_EDITOR", "true")
            .output()
            .expect("run git");
        assert!(
            output.status.success(),
            "git {arguments:?}: {}",
            String::from_utf8_lossy(&output.stderr)
        );
        String::from_utf8(output.stdout)
            .expect("utf-8 output")
            .trim()
            .to_owned()
    }

    fn write(&self, contents: &str) {
        fs::write(self.path().join("conflict.txt"), contents).expect("write fixture");
    }

    fn commit(&self, message: &str) -> String {
        self.git(&["add", "conflict.txt"]);
        self.git(&["commit", "-q", "-m", message]);
        self.git(&["rev-parse", "HEAD"])
    }
}

fn diverged_repository() -> (TestRepository, String) {
    let repository = TestRepository::new();
    repository.write("base\n");
    repository.commit("base");
    repository.git(&["checkout", "-q", "-b", "feature"]);
    repository.write("feature\n");
    let feature_commit = repository.commit("feature change");
    repository.git(&["checkout", "-q", "main"]);
    repository.write("main\n");
    repository.commit("main change");
    (repository, feature_commit)
}

#[test]
fn resolves_and_continues_a_conflicting_cherry_pick() {
    let (repository, feature_commit) = diverged_repository();

    assert!(gaji_core::cherry_pick(repository.path(), &feature_commit).is_err());
    let state = gaji_core::operation_state(repository.path()).expect("read operation state");
    assert_eq!(state.operation, Some(OperationKind::CherryPick));
    assert_eq!(state.conflicts, ["conflict.txt"]);
    let content = gaji_core::conflict_content(repository.path(), "conflict.txt").unwrap();
    assert_eq!(content.base.as_deref(), Some("base\n"));
    assert_eq!(content.ours.as_deref(), Some("main\n"));
    assert_eq!(content.theirs.as_deref(), Some("feature\n"));
    assert!(content.working.as_deref().unwrap().contains("<<<<<<<"));

    gaji_core::choose_conflict_side(repository.path(), "conflict.txt", ConflictSide::Theirs)
        .expect("choose incoming change");
    gaji_core::continue_operation(repository.path()).expect("continue cherry-pick");

    let state = gaji_core::operation_state(repository.path()).expect("read final state");
    assert_eq!(state.operation, None);
    assert!(state.conflicts.is_empty());
    assert_eq!(
        fs::read_to_string(repository.path().join("conflict.txt")).unwrap(),
        "feature\n"
    );
}

#[test]
fn cherry_picks_multiple_commits_in_order() {
    let repository = TestRepository::new();
    repository.write("base\n");
    repository.commit("base");
    repository.git(&["checkout", "-q", "-b", "feature"]);
    fs::write(repository.path().join("first.txt"), "first\n").unwrap();
    repository.git(&["add", "first.txt"]);
    repository.git(&["commit", "-q", "-m", "first"]);
    let first = repository.git(&["rev-parse", "HEAD"]);
    fs::write(repository.path().join("second.txt"), "second\n").unwrap();
    repository.git(&["add", "second.txt"]);
    repository.git(&["commit", "-q", "-m", "second"]);
    let second = repository.git(&["rev-parse", "HEAD"]);
    repository.git(&["checkout", "-q", "main"]);

    gaji_core::cherry_pick_many(repository.path(), &[&first, &second]).unwrap();

    assert_eq!(
        repository.git(&["log", "-2", "--reverse", "--format=%s"]),
        "first\nsecond"
    );
}

#[test]
fn aborts_a_conflicting_rebase() {
    let (repository, _) = diverged_repository();
    repository.git(&["checkout", "-q", "feature"]);
    let original_head = repository.git(&["rev-parse", "HEAD"]);

    assert!(gaji_core::rebase_onto(repository.path(), "main").is_err());
    let state = gaji_core::operation_state(repository.path()).expect("read operation state");
    assert_eq!(state.operation, Some(OperationKind::Rebase));
    assert_eq!(state.conflicts, ["conflict.txt"]);

    gaji_core::abort_operation(repository.path()).expect("abort rebase");
    assert_eq!(repository.git(&["rev-parse", "HEAD"]), original_head);
    assert_eq!(
        gaji_core::operation_state(repository.path())
            .unwrap()
            .operation,
        None
    );
}

#[test]
fn executes_a_validated_interactive_rebase_plan() {
    let repository = TestRepository::new();
    repository.write("base\n");
    let base = repository.commit("base");

    fs::write(repository.path().join("first.txt"), "first\n").unwrap();
    repository.git(&["add", "first.txt"]);
    repository.git(&["commit", "-q", "-m", "first"]);
    fs::write(repository.path().join("second.txt"), "second\n").unwrap();
    repository.git(&["add", "second.txt"]);
    repository.git(&["commit", "-q", "-m", "second"]);

    let mut plan = gaji_core::interactive_rebase_plan(repository.path(), &base).unwrap();
    assert_eq!(plan.len(), 2);
    plan.swap(0, 1);
    gaji_core::start_interactive_rebase(repository.path(), &base, &plan).unwrap();

    assert_eq!(
        repository.git(&["log", "--reverse", "--format=%s"]),
        "base\nsecond\nfirst"
    );
}
