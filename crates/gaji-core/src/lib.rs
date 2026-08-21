use std::path::{Path, PathBuf};
use std::process::Command;

use serde::Serialize;
use thiserror::Error;

mod workflow;
pub use workflow::*;
mod rebase;
pub use rebase::*;

#[derive(Debug, Error)]
pub enum GajiError {
    #[error("could not start git: {0}")]
    GitUnavailable(#[from] std::io::Error),
    #[error("git command failed: {0}")]
    GitFailed(String),
    #[error("git returned non-UTF-8 output")]
    InvalidOutput,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RepositorySnapshot {
    pub root: PathBuf,
    pub branch: String,
    pub changes: Vec<WorkingTreeChange>,
    pub recent_commits: Vec<CommitSummary>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkingTreeChange {
    pub index_status: char,
    pub worktree_status: char,
    pub path: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CommitSummary {
    pub id: String,
    pub author: String,
    pub authored_at: String,
    pub subject: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum OperationKind {
    CherryPick,
    Rebase,
    Merge,
    Revert,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct OperationState {
    pub operation: Option<OperationKind>,
    pub conflicts: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ConflictContent {
    pub path: String,
    pub base: Option<String>,
    pub ours: Option<String>,
    pub theirs: Option<String>,
    pub working: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ConflictSide {
    Ours,
    Theirs,
}

pub fn inspect_repository(path: impl AsRef<Path>) -> Result<RepositorySnapshot, GajiError> {
    let path = path.as_ref();
    let root = PathBuf::from(git(path, &["rev-parse", "--show-toplevel"])?.trim());
    let branch = git(&root, &["branch", "--show-current"])?;
    let branch = if branch.trim().is_empty() {
        git(&root, &["rev-parse", "--short", "HEAD"])?
    } else {
        branch
    };

    let status = git(&root, &["status", "--porcelain=v1", "-z"])?;
    let changes = parse_status(&status);
    let log = match git(
        &root,
        &[
            "log",
            "-n",
            "30",
            "--date=iso-strict",
            "--pretty=format:%H%x1f%an%x1f%aI%x1f%s%x1e",
        ],
    ) {
        Ok(log) => log,
        Err(GajiError::GitFailed(_)) => String::new(),
        Err(error) => return Err(error),
    };

    Ok(RepositorySnapshot {
        root,
        branch: branch.trim().to_owned(),
        changes,
        recent_commits: parse_log(&log),
    })
}

pub fn operation_state(path: impl AsRef<Path>) -> Result<OperationState, GajiError> {
    let root = repository_root(path.as_ref())?;
    let operation =
        if git_path(&root, "rebase-merge")?.is_dir() || git_path(&root, "rebase-apply")?.is_dir() {
            Some(OperationKind::Rebase)
        } else if git_path(&root, "CHERRY_PICK_HEAD")?.is_file() {
            Some(OperationKind::CherryPick)
        } else if git_path(&root, "MERGE_HEAD")?.is_file() {
            Some(OperationKind::Merge)
        } else if git_path(&root, "REVERT_HEAD")?.is_file() {
            Some(OperationKind::Revert)
        } else {
            None
        };

    let output = git(&root, &["diff", "--name-only", "--diff-filter=U", "-z"])?;
    let conflicts = output
        .split('\0')
        .filter(|path| !path.is_empty())
        .map(str::to_owned)
        .collect();

    Ok(OperationState {
        operation,
        conflicts,
    })
}

pub fn conflict_content(path: impl AsRef<Path>, file: &str) -> Result<ConflictContent, GajiError> {
    let root = repository_root(path.as_ref())?;
    let conflicts = operation_state(&root)?.conflicts;
    if !conflicts.iter().any(|candidate| candidate == file) {
        return Err(GajiError::GitFailed(format!(
            "{file} is not an unresolved conflict"
        )));
    }
    Ok(ConflictContent {
        path: file.to_owned(),
        base: conflict_stage(&root, 1, file)?,
        ours: conflict_stage(&root, 2, file)?,
        theirs: conflict_stage(&root, 3, file)?,
        working: match std::fs::read(root.join(file)) {
            Ok(bytes) => String::from_utf8(bytes).ok(),
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => None,
            Err(error) => return Err(GajiError::GitUnavailable(error)),
        },
    })
}

fn conflict_stage(root: &Path, stage: u8, file: &str) -> Result<Option<String>, GajiError> {
    match git(root, &["show", &format!(":{stage}:{file}")]) {
        Ok(contents) => Ok(Some(contents)),
        Err(GajiError::GitFailed(_)) => Ok(None),
        Err(error) => Err(error),
    }
}

pub fn cherry_pick(path: impl AsRef<Path>, revision: &str) -> Result<(), GajiError> {
    cherry_pick_many(path, &[revision])
}

pub fn cherry_pick_many(path: impl AsRef<Path>, revisions: &[&str]) -> Result<(), GajiError> {
    if revisions.is_empty() {
        return Err(GajiError::GitFailed("no commits selected".to_owned()));
    }
    let root = repository_root(path.as_ref())?;
    let commits = revisions
        .iter()
        .map(|revision| resolve_commit(&root, revision))
        .collect::<Result<Vec<_>, _>>()?;
    let mut arguments = vec!["cherry-pick"];
    arguments.extend(commits.iter().map(String::as_str));
    git(&root, &arguments).map(|_| ())
}

pub fn rebase_onto(path: impl AsRef<Path>, upstream: &str) -> Result<(), GajiError> {
    let root = repository_root(path.as_ref())?;
    let commit = resolve_commit(&root, upstream)?;
    git(&root, &["rebase", &commit]).map(|_| ())
}

pub fn continue_operation(path: impl AsRef<Path>) -> Result<(), GajiError> {
    let root = repository_root(path.as_ref())?;
    let state = operation_state(&root)?;
    if !state.conflicts.is_empty() {
        return Err(GajiError::GitFailed(format!(
            "{} conflict(s) still need resolution",
            state.conflicts.len()
        )));
    }

    match state.operation {
        Some(OperationKind::Rebase) => git(&root, &["rebase", "--continue"]),
        Some(OperationKind::CherryPick) => git(&root, &["cherry-pick", "--continue"]),
        Some(OperationKind::Merge) => git(&root, &["commit", "--no-edit"]),
        Some(OperationKind::Revert) => git(&root, &["revert", "--continue"]),
        None => return Err(GajiError::GitFailed("no operation to continue".to_owned())),
    }
    .map(|_| ())
}

pub fn abort_operation(path: impl AsRef<Path>) -> Result<(), GajiError> {
    let root = repository_root(path.as_ref())?;
    match operation_state(&root)?.operation {
        Some(OperationKind::Rebase) => git(&root, &["rebase", "--abort"]),
        Some(OperationKind::CherryPick) => git(&root, &["cherry-pick", "--abort"]),
        Some(OperationKind::Merge) => git(&root, &["merge", "--abort"]),
        Some(OperationKind::Revert) => git(&root, &["revert", "--abort"]),
        None => return Err(GajiError::GitFailed("no operation to abort".to_owned())),
    }
    .map(|_| ())
}

pub fn choose_conflict_side(
    path: impl AsRef<Path>,
    file: &str,
    side: ConflictSide,
) -> Result<(), GajiError> {
    let root = repository_root(path.as_ref())?;
    let option = match side {
        ConflictSide::Ours => "--ours",
        ConflictSide::Theirs => "--theirs",
    };
    git(&root, &["checkout", option, "--", file])?;
    mark_resolved(&root, file)
}

pub fn mark_resolved(path: impl AsRef<Path>, file: &str) -> Result<(), GajiError> {
    let root = repository_root(path.as_ref())?;
    git(&root, &["add", "--", file]).map(|_| ())
}

fn repository_root(path: &Path) -> Result<PathBuf, GajiError> {
    Ok(PathBuf::from(
        git(path, &["rev-parse", "--show-toplevel"])?.trim(),
    ))
}

fn resolve_commit(root: &Path, revision: &str) -> Result<String, GajiError> {
    git(
        root,
        &["rev-parse", "--verify", &format!("{revision}^{{commit}}")],
    )
    .map(|output| output.trim().to_owned())
}

fn git_path(root: &Path, name: &str) -> Result<PathBuf, GajiError> {
    let output = git(
        root,
        &["rev-parse", "--path-format=absolute", "--git-path", name],
    )?;
    Ok(PathBuf::from(output.trim()))
}

pub(crate) fn git(directory: &Path, arguments: &[&str]) -> Result<String, GajiError> {
    let output = Command::new("git")
        .args(["-C", directory.to_string_lossy().as_ref()])
        .args(arguments)
        .env("GIT_EDITOR", "true")
        .env("GIT_SEQUENCE_EDITOR", "true")
        .env("GIT_OPTIONAL_LOCKS", "0")
        .output()?;

    if !output.status.success() {
        let message = String::from_utf8_lossy(&output.stderr).trim().to_owned();
        return Err(GajiError::GitFailed(message));
    }

    String::from_utf8(output.stdout).map_err(|_| GajiError::InvalidOutput)
}

fn parse_status(output: &str) -> Vec<WorkingTreeChange> {
    let mut entries = output.split('\0').filter(|entry| !entry.is_empty());
    let mut changes = Vec::new();

    while let Some(entry) = entries.next() {
        if entry.len() < 4 {
            continue;
        }

        let change = WorkingTreeChange {
            index_status: entry.chars().next().unwrap_or(' '),
            worktree_status: entry.chars().nth(1).unwrap_or(' '),
            path: entry[3..].to_owned(),
        };

        if matches!(change.index_status, 'R' | 'C') {
            let _original_path = entries.next();
        }
        changes.push(change);
    }

    changes
}

fn parse_log(output: &str) -> Vec<CommitSummary> {
    output
        .split('\x1e')
        .filter_map(|record| {
            let mut fields = record.trim().splitn(4, '\x1f');
            Some(CommitSummary {
                id: fields.next()?.to_owned(),
                author: fields.next()?.to_owned(),
                authored_at: fields.next()?.to_owned(),
                subject: fields.next()?.to_owned(),
            })
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_porcelain_status() {
        let changes = parse_status(" M src/main.rs\0A  README.md\0?? notes.txt\0");
        assert_eq!(changes.len(), 3);
        assert_eq!(changes[0].worktree_status, 'M');
        assert_eq!(changes[1].index_status, 'A');
        assert_eq!(changes[2].path, "notes.txt");
    }

    #[test]
    fn parses_log_records() {
        let commits = parse_log("abc\x1fAda\x1f2026-08-19T12:00:00+09:00\x1fInitial commit\x1e");
        assert_eq!(commits.len(), 1);
        assert_eq!(commits[0].subject, "Initial commit");
    }

    #[test]
    fn consumes_original_path_for_renames() {
        let changes = parse_status("R  new.txt\0old.txt\0?? another.txt\0");
        assert_eq!(changes.len(), 2);
        assert_eq!(changes[0].path, "new.txt");
        assert_eq!(changes[1].path, "another.txt");
    }
}
