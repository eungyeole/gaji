use std::collections::HashSet;
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::atomic::{AtomicU64, Ordering};

use serde::{Deserialize, Serialize};

use crate::{GajiError, git};

static TEMP_SEQUENCE: AtomicU64 = AtomicU64::new(0);

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum RebaseAction {
    Pick,
    Reword,
    Edit,
    Squash,
    Fixup,
    Drop,
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RebaseStep {
    pub action: RebaseAction,
    pub commit: String,
    pub subject: String,
}

pub fn interactive_rebase_plan(
    path: impl AsRef<Path>,
    upstream: &str,
) -> Result<Vec<RebaseStep>, GajiError> {
    let root = repository_root(path.as_ref())?;
    let upstream = resolve_commit(&root, upstream)?;
    let range = format!("{upstream}..HEAD");
    let output = git(
        &root,
        &["log", "--reverse", "--format=%H%x1f%s%x1e", &range],
    )?;
    Ok(output
        .split('\x1e')
        .filter_map(|record| {
            let (commit, subject) = record.trim().split_once('\x1f')?;
            Some(RebaseStep {
                action: RebaseAction::Pick,
                commit: commit.to_owned(),
                subject: subject.to_owned(),
            })
        })
        .collect())
}

pub fn start_interactive_rebase(
    path: impl AsRef<Path>,
    upstream: &str,
    steps: &[RebaseStep],
) -> Result<(), GajiError> {
    let root = repository_root(path.as_ref())?;
    let upstream = resolve_commit(&root, upstream)?;
    validate_plan(&root, &upstream, steps)?;

    let todo = steps
        .iter()
        .map(|step| {
            format!(
                "{} {} {}",
                action_name(step.action),
                step.commit,
                step.subject.replace(['\n', '\r'], " ")
            )
        })
        .collect::<Vec<_>>()
        .join("\n");
    let files = SequenceEditorFiles::create(&todo)?;
    let output = Command::new("git")
        .args([
            "-C",
            root.to_string_lossy().as_ref(),
            "rebase",
            "-i",
            &upstream,
        ])
        .env("GIT_SEQUENCE_EDITOR", files.command())
        .env("GAJI_REBASE_TODO", &files.todo)
        .env("GIT_EDITOR", "true")
        .output()?;

    if output.status.success() {
        Ok(())
    } else {
        Err(GajiError::GitFailed(
            String::from_utf8_lossy(&output.stderr).trim().to_owned(),
        ))
    }
}

fn validate_plan(root: &Path, upstream: &str, steps: &[RebaseStep]) -> Result<(), GajiError> {
    let expected = interactive_rebase_plan(root, upstream)?;
    if expected.len() != steps.len() {
        return Err(GajiError::GitFailed(
            "rebase plan must contain every commit exactly once".to_owned(),
        ));
    }
    let expected: HashSet<&str> = expected.iter().map(|step| step.commit.as_str()).collect();
    let actual: HashSet<&str> = steps.iter().map(|step| step.commit.as_str()).collect();
    if expected != actual || actual.len() != steps.len() {
        return Err(GajiError::GitFailed(
            "rebase plan contains an unknown or duplicate commit".to_owned(),
        ));
    }
    if matches!(
        steps.first().map(|step| step.action),
        Some(RebaseAction::Squash | RebaseAction::Fixup)
    ) {
        return Err(GajiError::GitFailed(
            "the first rebase step cannot be squash or fixup".to_owned(),
        ));
    }
    Ok(())
}

fn action_name(action: RebaseAction) -> &'static str {
    match action {
        RebaseAction::Pick => "pick",
        RebaseAction::Reword => "reword",
        RebaseAction::Edit => "edit",
        RebaseAction::Squash => "squash",
        RebaseAction::Fixup => "fixup",
        RebaseAction::Drop => "drop",
    }
}

fn repository_root(path: &Path) -> Result<PathBuf, GajiError> {
    Ok(PathBuf::from(
        git(path, &["rev-parse", "--show-toplevel"])?.trim(),
    ))
}

fn resolve_commit(root: &Path, revision: &str) -> Result<String, GajiError> {
    if revision.trim().is_empty() {
        return Err(GajiError::GitFailed("upstream cannot be empty".to_owned()));
    }
    git(
        root,
        &["rev-parse", "--verify", &format!("{revision}^{{commit}}")],
    )
    .map(|output| output.trim().to_owned())
}

struct SequenceEditorFiles {
    todo: PathBuf,
    editor: PathBuf,
}

impl SequenceEditorFiles {
    fn create(todo: &str) -> Result<Self, GajiError> {
        let nonce = TEMP_SEQUENCE.fetch_add(1, Ordering::Relaxed);
        let stem = format!("gaji-rebase-{}-{nonce}", std::process::id());
        let directory = std::env::temp_dir();
        let todo_path = directory.join(format!("{stem}.todo"));
        #[cfg(windows)]
        let editor_path = directory.join(format!("{stem}.cmd"));
        #[cfg(not(windows))]
        let editor_path = directory.join(format!("{stem}.sh"));

        create_file(&todo_path, todo)?;
        #[cfg(windows)]
        create_file(
            &editor_path,
            "@copy /Y \"%GAJI_REBASE_TODO%\" \"%~1\" >NUL\r\n",
        )?;
        #[cfg(not(windows))]
        {
            create_file(&editor_path, "#!/bin/sh\ncp \"$GAJI_REBASE_TODO\" \"$1\"\n")?;
            use std::os::unix::fs::PermissionsExt;
            fs::set_permissions(&editor_path, fs::Permissions::from_mode(0o700))?;
        }

        Ok(Self {
            todo: todo_path,
            editor: editor_path,
        })
    }

    fn command(&self) -> String {
        format!("\"{}\"", self.editor.to_string_lossy().replace('\\', "/"))
    }
}

impl Drop for SequenceEditorFiles {
    fn drop(&mut self) {
        let _ = fs::remove_file(&self.todo);
        let _ = fs::remove_file(&self.editor);
    }
}

fn create_file(path: &Path, contents: &str) -> Result<(), GajiError> {
    let mut file = OpenOptions::new().write(true).create_new(true).open(path)?;
    file.write_all(contents.as_bytes())?;
    Ok(())
}
