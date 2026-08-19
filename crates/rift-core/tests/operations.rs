use std::fs;
use std::path::Path;
use std::process::Command;

use rift_core::{ConflictSide, OperationKind};
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
        repository.git(&["config", "user.name", "Rift Test"]);
        repository.git(&["config", "user.email", "rift@example.invalid"]);
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

    assert!(rift_core::cherry_pick(repository.path(), &feature_commit).is_err());
    let state = rift_core::operation_state(repository.path()).expect("read operation state");
    assert_eq!(state.operation, Some(OperationKind::CherryPick));
    assert_eq!(state.conflicts, ["conflict.txt"]);

    rift_core::choose_conflict_side(repository.path(), "conflict.txt", ConflictSide::Theirs)
        .expect("choose incoming change");
    rift_core::continue_operation(repository.path()).expect("continue cherry-pick");

    let state = rift_core::operation_state(repository.path()).expect("read final state");
    assert_eq!(state.operation, None);
    assert!(state.conflicts.is_empty());
    assert_eq!(
        fs::read_to_string(repository.path().join("conflict.txt")).unwrap(),
        "feature\n"
    );
}

#[test]
fn aborts_a_conflicting_rebase() {
    let (repository, _) = diverged_repository();
    repository.git(&["checkout", "-q", "feature"]);
    let original_head = repository.git(&["rev-parse", "HEAD"]);

    assert!(rift_core::rebase_onto(repository.path(), "main").is_err());
    let state = rift_core::operation_state(repository.path()).expect("read operation state");
    assert_eq!(state.operation, Some(OperationKind::Rebase));
    assert_eq!(state.conflicts, ["conflict.txt"]);

    rift_core::abort_operation(repository.path()).expect("abort rebase");
    assert_eq!(repository.git(&["rev-parse", "HEAD"]), original_head);
    assert_eq!(
        rift_core::operation_state(repository.path())
            .unwrap()
            .operation,
        None
    );
}
