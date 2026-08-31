use std::collections::{HashMap, HashSet};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

use serde::Serialize;

use crate::{GajiError, git};

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DiffSummary {
    pub path: String,
    pub additions: Option<u32>,
    pub deletions: Option<u32>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DiffHunk {
    pub id: usize,
    pub header: String,
    pub patch: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FileDiffDetails {
    pub patch: String,
    pub hunks: Vec<DiffHunk>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BranchSummary {
    pub name: String,
    pub commit: String,
    pub upstream: Option<String>,
    pub is_current: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RemoteSummary {
    pub name: String,
    pub fetch_url: String,
    pub push_url: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct StashSummary {
    pub index: usize,
    pub commit: String,
    pub reference: String,
    pub subject: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct HistoryEntry {
    pub id: String,
    pub author: String,
    pub authored_at: String,
    pub subject: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum GraphCommitKind {
    Commit,
    Stash,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum GraphReferenceKind {
    Head,
    LocalBranch,
    RemoteBranch,
    Tag,
    Stash,
    Other,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct GraphReference {
    pub name: String,
    pub full_name: String,
    pub kind: GraphReferenceKind,
    pub is_current: bool,
    pub is_suppressed: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct GraphCommit {
    pub id: String,
    pub parents: Vec<String>,
    /// Compact, display-oriented decorations kept for API compatibility.
    pub references: Vec<String>,
    /// All refs for this commit, including remote aliases suppressed from `references`.
    pub reference_details: Vec<GraphReference>,
    pub kind: GraphCommitKind,
    pub is_stash: bool,
    pub author: String,
    pub author_email: String,
    pub authored_at: String,
    pub subject: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CommitFileChange {
    pub status: String,
    pub path: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BlameLine {
    pub line_number: usize,
    pub commit: String,
    pub author: String,
    pub authored_at: i64,
    pub content: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WorktreeSummary {
    pub path: PathBuf,
    pub commit: String,
    pub branch: Option<String>,
    pub is_bare: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SubmoduleSummary {
    pub path: String,
    pub commit: String,
    pub state: char,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ResetMode {
    Soft,
    Mixed,
    Hard,
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct CommitOptions {
    pub amend: bool,
    pub sign: bool,
    pub signoff: bool,
    pub allow_empty: bool,
}

pub fn diff_summary(path: impl AsRef<Path>, staged: bool) -> Result<Vec<DiffSummary>, GajiError> {
    let root = root(path.as_ref())?;
    let mut arguments = vec!["diff", "--numstat", "-z"];
    if staged {
        arguments.push("--cached");
    }
    let output = git(&root, &arguments)?;
    Ok(output
        .split('\0')
        .filter_map(|record| {
            let mut fields = record.splitn(3, '\t');
            let additions = parse_count(fields.next()?);
            let deletions = parse_count(fields.next()?);
            let path = fields.next()?.to_owned();
            Some(DiffSummary {
                path,
                additions,
                deletions,
            })
        })
        .collect())
}

pub fn file_diff(path: impl AsRef<Path>, file: &str, staged: bool) -> Result<String, GajiError> {
    let root = root(path.as_ref())?;
    if staged {
        git(&root, &["diff", "--cached", "--no-ext-diff", "--", file])
    } else {
        git(&root, &["diff", "--no-ext-diff", "--", file])
    }
}

pub fn file_hunks(
    path: impl AsRef<Path>,
    file: &str,
    staged: bool,
) -> Result<Vec<DiffHunk>, GajiError> {
    file_diff_details(path, file, staged).map(|details| details.hunks)
}

pub fn file_diff_details(
    path: impl AsRef<Path>,
    file: &str,
    staged: bool,
) -> Result<FileDiffDetails, GajiError> {
    let patch = file_diff(path, file, staged)?;
    let hunks = parse_hunks(&patch);
    Ok(FileDiffDetails { patch, hunks })
}

pub fn apply_diff_patch(
    path: impl AsRef<Path>,
    patch: &str,
    staged: bool,
    reverse: bool,
) -> Result<(), GajiError> {
    require_value("patch", patch)?;
    let root = root(path.as_ref())?;
    let root_path = root.to_string_lossy();
    let mut arguments = vec!["-C", root_path.as_ref(), "apply"];
    if staged {
        arguments.push("--cached");
    }
    if reverse {
        arguments.push("--reverse");
    }
    arguments.extend(["--recount", "--whitespace=nowarn", "-"]);
    git_with_input(&arguments, patch).map(|_| ())
}

pub fn stage(path: impl AsRef<Path>, files: &[&str]) -> Result<(), GajiError> {
    paths_command(path.as_ref(), &["add"], files)
}

pub fn unstage(path: impl AsRef<Path>, files: &[&str]) -> Result<(), GajiError> {
    paths_command(path.as_ref(), &["restore", "--staged"], files)
}

pub fn discard(path: impl AsRef<Path>, files: &[&str]) -> Result<(), GajiError> {
    if files.is_empty() {
        return Err(GajiError::GitFailed("no files selected".to_owned()));
    }
    let root = root(path.as_ref())?;
    let (tracked, untracked): (Vec<_>, Vec<_>) = files
        .iter()
        .partition(|file| git(&root, &["ls-files", "--error-unmatch", "--", file]).is_ok());
    if !tracked.is_empty() {
        let tracked: Vec<&str> = tracked.into_iter().copied().collect();
        paths_command(&root, &["restore", "--worktree"], &tracked)?;
    }
    if !untracked.is_empty() {
        let untracked: Vec<&str> = untracked.into_iter().copied().collect();
        paths_command(&root, &["clean", "-fd"], &untracked)?;
    }
    Ok(())
}

pub fn commit(path: impl AsRef<Path>, message: &str, amend: bool) -> Result<String, GajiError> {
    commit_with_options(
        path,
        message,
        CommitOptions {
            amend,
            ..CommitOptions::default()
        },
    )
}

pub fn commit_with_options(
    path: impl AsRef<Path>,
    message: &str,
    options: CommitOptions,
) -> Result<String, GajiError> {
    require_value("commit message", message)?;
    let root = root(path.as_ref())?;
    let mut arguments = vec!["commit"];
    if options.amend {
        arguments.push("--amend");
    }
    if options.sign {
        arguments.push("-S");
    }
    if options.signoff {
        arguments.push("--signoff");
    }
    if options.allow_empty {
        arguments.push("--allow-empty");
    }
    arguments.extend(["-m", message]);
    git(&root, &arguments)?;
    git(&root, &["rev-parse", "HEAD"]).map(|value| value.trim().to_owned())
}

pub fn branches(path: impl AsRef<Path>) -> Result<Vec<BranchSummary>, GajiError> {
    let root = root(path.as_ref())?;
    let output = git(
        &root,
        &[
            "for-each-ref",
            "refs/heads",
            "--format=%(refname:short)%00%(objectname)%00%(upstream:short)%00%(HEAD)%00",
        ],
    )?;
    let fields: Vec<&str> = output.split('\0').collect();
    Ok(fields
        .chunks(4)
        .filter_map(|item| {
            if item.len() < 4 || item[0].is_empty() {
                return None;
            }
            Some(BranchSummary {
                name: item[0].to_owned(),
                commit: item[1].to_owned(),
                upstream: (!item[2].is_empty()).then(|| item[2].to_owned()),
                is_current: item[3].trim() == "*",
            })
        })
        .collect())
}

pub fn switch_branch(path: impl AsRef<Path>, branch: &str) -> Result<(), GajiError> {
    let root = root(path.as_ref())?;
    let reference = verify_branch(&root, branch)?;
    git(&root, &["switch", &reference]).map(|_| ())
}

pub fn create_branch(
    path: impl AsRef<Path>,
    name: &str,
    start: &str,
    switch: bool,
) -> Result<(), GajiError> {
    require_ref_name(name)?;
    let root = root(path.as_ref())?;
    let commit = resolve_commit(&root, start)?;
    let is_remote_branch = git(
        &root,
        &["show-ref", "--verify", &format!("refs/remotes/{start}")],
    )
    .is_ok();
    if switch && is_remote_branch {
        git(&root, &["switch", "-c", name, "--track", start])
    } else if switch {
        git(&root, &["switch", "-c", name, &commit])
    } else {
        git(&root, &["branch", name, &commit])
    }
    .map(|_| ())
}

pub fn delete_branch(path: impl AsRef<Path>, name: &str, force: bool) -> Result<(), GajiError> {
    let root = root(path.as_ref())?;
    let branch = verify_branch(&root, name)?;
    git(&root, &["branch", if force { "-D" } else { "-d" }, &branch]).map(|_| ())
}

pub fn rename_branch(path: impl AsRef<Path>, old: &str, new: &str) -> Result<(), GajiError> {
    require_ref_name(new)?;
    let root = root(path.as_ref())?;
    let old = verify_branch(&root, old)?;
    git(&root, &["branch", "-m", &old, new]).map(|_| ())
}

pub fn remotes(path: impl AsRef<Path>) -> Result<Vec<RemoteSummary>, GajiError> {
    let root = root(path.as_ref())?;
    let names = git(&root, &["remote"])?;
    names
        .lines()
        .map(|name| {
            let fetch_url = git(&root, &["remote", "get-url", name])?.trim().to_owned();
            let push_url = git(&root, &["remote", "get-url", "--push", name])?
                .trim()
                .to_owned();
            Ok(RemoteSummary {
                name: name.to_owned(),
                fetch_url,
                push_url,
            })
        })
        .collect()
}

pub fn add_remote(path: impl AsRef<Path>, name: &str, url: &str) -> Result<(), GajiError> {
    require_ref_name(name)?;
    require_value("remote URL", url)?;
    let root = root(path.as_ref())?;
    git(&root, &["remote", "add", name, url]).map(|_| ())
}

pub fn set_remote_url(
    path: impl AsRef<Path>,
    name: &str,
    url: &str,
    push: bool,
) -> Result<(), GajiError> {
    require_value("remote URL", url)?;
    let root = root(path.as_ref())?;
    if push {
        git(&root, &["remote", "set-url", "--push", name, url])
    } else {
        git(&root, &["remote", "set-url", name, url])
    }
    .map(|_| ())
}

pub fn remove_remote(path: impl AsRef<Path>, name: &str) -> Result<(), GajiError> {
    let root = root(path.as_ref())?;
    git(&root, &["remote", "remove", name]).map(|_| ())
}

pub fn fetch(path: impl AsRef<Path>, remote: &str, prune: bool) -> Result<(), GajiError> {
    let root = root(path.as_ref())?;
    if prune {
        git(&root, &["fetch", "--prune", "--", remote])
    } else {
        git(&root, &["fetch", "--", remote])
    }
    .map(|_| ())
}

pub fn pull(
    path: impl AsRef<Path>,
    rebase: bool,
    fast_forward_only: bool,
) -> Result<(), GajiError> {
    let root = root(path.as_ref())?;
    let mode = if rebase {
        "--rebase"
    } else if fast_forward_only {
        "--ff-only"
    } else {
        "--no-rebase"
    };
    git(&root, &["pull", mode]).map(|_| ())
}

pub fn push(
    path: impl AsRef<Path>,
    remote: &str,
    branch: &str,
    set_upstream: bool,
    force_with_lease: bool,
) -> Result<(), GajiError> {
    let root = root(path.as_ref())?;
    let branch = verify_branch(&root, branch)?;
    let mut arguments = vec!["push"];
    if set_upstream {
        arguments.push("--set-upstream");
    }
    if force_with_lease {
        arguments.push("--force-with-lease");
    }
    arguments.extend(["--", remote, &branch]);
    git(&root, &arguments).map(|_| ())
}

pub fn stashes(path: impl AsRef<Path>) -> Result<Vec<StashSummary>, GajiError> {
    let root = root(path.as_ref())?;
    let output = git(&root, &["stash", "list", "-z", "--format=%H%x00%gd%x00%s"])?;
    let fields: Vec<&str> = output.split('\0').collect();
    Ok(fields
        .chunks(3)
        .enumerate()
        .filter_map(|(index, item)| {
            if item.len() < 3 || item[0].is_empty() {
                return None;
            }
            Some(StashSummary {
                index,
                commit: item[0].to_owned(),
                reference: item[1].to_owned(),
                subject: item[2].to_owned(),
            })
        })
        .collect())
}

pub fn stash_files(
    path: impl AsRef<Path>,
    index: usize,
) -> Result<Vec<CommitFileChange>, GajiError> {
    let root = root(path.as_ref())?;
    let reference = format!("stash@{{{index}}}");
    let output = git(
        &root,
        &[
            "diff",
            "--name-status",
            "-M",
            &format!("{reference}^1"),
            &reference,
        ],
    )?;
    let mut files: Vec<_> = output
        .lines()
        .filter_map(|line| {
            let fields: Vec<_> = line.split('\t').collect();
            Some(CommitFileChange {
                status: fields.first()?.to_string(),
                path: fields.last()?.to_string(),
            })
        })
        .collect();

    let untracked = format!("{reference}^3");
    if let Ok(output) = git(&root, &["ls-tree", "-r", "--name-only", &untracked]) {
        for path in output.lines().filter(|path| !path.is_empty()) {
            if !files.iter().any(|file| file.path == path) {
                files.push(CommitFileChange {
                    status: "A".to_owned(),
                    path: path.to_owned(),
                });
            }
        }
    }
    Ok(files)
}

pub fn stash_file_diff(
    path: impl AsRef<Path>,
    index: usize,
    file: &str,
) -> Result<String, GajiError> {
    require_value("file", file)?;
    let root = root(path.as_ref())?;
    let reference = format!("stash@{{{index}}}");
    let untracked = format!("{reference}^3");
    let untracked_file = format!("{untracked}:{file}");
    if git(&root, &["cat-file", "-e", &untracked_file]).is_ok() {
        return git(
            &root,
            &["show", "--root", "--format=", &untracked, "--", file],
        );
    }
    git(
        &root,
        &[
            "diff",
            "--find-renames",
            &format!("{reference}^1"),
            &reference,
            "--",
            file,
        ],
    )
}

pub fn stash_push(
    path: impl AsRef<Path>,
    message: &str,
    include_untracked: bool,
) -> Result<(), GajiError> {
    let root = root(path.as_ref())?;
    if include_untracked {
        git(&root, &["stash", "push", "-u", "-m", message])
    } else {
        git(&root, &["stash", "push", "-m", message])
    }
    .map(|_| ())
}

pub fn stash_apply(path: impl AsRef<Path>, index: usize, pop: bool) -> Result<(), GajiError> {
    let root = root(path.as_ref())?;
    let reference = format!("stash@{{{index}}}");
    git(
        &root,
        &["stash", if pop { "pop" } else { "apply" }, &reference],
    )
    .map(|_| ())
}

pub fn stash_drop(path: impl AsRef<Path>, index: usize) -> Result<(), GajiError> {
    let root = root(path.as_ref())?;
    let reference = format!("stash@{{{index}}}");
    git(&root, &["stash", "drop", &reference]).map(|_| ())
}

pub fn tags(path: impl AsRef<Path>) -> Result<Vec<String>, GajiError> {
    let root = root(path.as_ref())?;
    Ok(git(&root, &["tag", "--list"])?
        .lines()
        .map(str::to_owned)
        .collect())
}

pub fn create_tag(
    path: impl AsRef<Path>,
    name: &str,
    target: &str,
    message: Option<&str>,
) -> Result<(), GajiError> {
    require_ref_name(name)?;
    let root = root(path.as_ref())?;
    let commit = resolve_commit(&root, target)?;
    match message {
        Some(message) => git(&root, &["tag", "-a", name, &commit, "-m", message]),
        None => git(&root, &["tag", name, &commit]),
    }
    .map(|_| ())
}

pub fn delete_tag(path: impl AsRef<Path>, name: &str) -> Result<(), GajiError> {
    let root = root(path.as_ref())?;
    git(&root, &["tag", "-d", "--", name]).map(|_| ())
}

pub fn push_tag(path: impl AsRef<Path>, remote: &str, name: &str) -> Result<(), GajiError> {
    require_ref_name(name)?;
    let root = root(path.as_ref())?;
    git(&root, &["push", "--", remote, &format!("refs/tags/{name}")]).map(|_| ())
}

pub fn reset(path: impl AsRef<Path>, target: &str, mode: ResetMode) -> Result<(), GajiError> {
    let root = root(path.as_ref())?;
    let commit = resolve_commit(&root, target)?;
    let mode = match mode {
        ResetMode::Soft => "--soft",
        ResetMode::Mixed => "--mixed",
        ResetMode::Hard => "--hard",
    };
    git(&root, &["reset", mode, &commit]).map(|_| ())
}

pub fn revert(path: impl AsRef<Path>, target: &str) -> Result<(), GajiError> {
    let root = root(path.as_ref())?;
    let commit = resolve_commit(&root, target)?;
    git(&root, &["revert", "--no-edit", &commit]).map(|_| ())
}

pub fn merge(
    path: impl AsRef<Path>,
    revision: &str,
    no_fast_forward: bool,
) -> Result<(), GajiError> {
    let root = root(path.as_ref())?;
    let commit = resolve_commit(&root, revision)?;
    if no_fast_forward {
        git(&root, &["merge", "--no-ff", "--no-edit", &commit])
    } else {
        git(&root, &["merge", "--no-edit", &commit])
    }
    .map(|_| ())
}

pub fn file_history(path: impl AsRef<Path>, file: &str) -> Result<Vec<HistoryEntry>, GajiError> {
    let root = root(path.as_ref())?;
    let output = git(
        &root,
        &[
            "log",
            "--follow",
            "--date=iso-strict",
            "--pretty=format:%H%x1f%an%x1f%aI%x1f%s%x1e",
            "--",
            file,
        ],
    )?;
    Ok(output
        .split('\x1e')
        .filter_map(|record| {
            let mut fields = record.trim().splitn(4, '\x1f');
            Some(HistoryEntry {
                id: fields.next()?.to_owned(),
                author: fields.next()?.to_owned(),
                authored_at: fields.next()?.to_owned(),
                subject: fields.next()?.to_owned(),
            })
        })
        .collect())
}

pub fn blame(path: impl AsRef<Path>, file: &str) -> Result<Vec<BlameLine>, GajiError> {
    let root = root(path.as_ref())?;
    let output = git(&root, &["blame", "--line-porcelain", "--", file])?;
    let mut lines = output.lines().peekable();
    let mut result = Vec::new();
    while let Some(header) = lines.next() {
        let fields: Vec<&str> = header.split_whitespace().collect();
        if fields.len() < 3 || fields[0].len() < 8 {
            continue;
        }
        let commit = fields[0].to_owned();
        let line_number = fields[2].parse().unwrap_or(0);
        let mut author = String::new();
        let mut authored_at = 0;
        let mut content = String::new();
        for line in lines.by_ref() {
            if let Some(value) = line.strip_prefix("author ") {
                author = value.to_owned();
            } else if let Some(value) = line.strip_prefix("author-time ") {
                authored_at = value.parse().unwrap_or(0);
            } else if let Some(value) = line.strip_prefix('\t') {
                content = value.to_owned();
                break;
            }
        }
        result.push(BlameLine {
            line_number,
            commit,
            author,
            authored_at,
            content,
        });
    }
    Ok(result)
}

pub fn worktrees(path: impl AsRef<Path>) -> Result<Vec<WorktreeSummary>, GajiError> {
    let root = root(path.as_ref())?;
    let output = git(&root, &["worktree", "list", "--porcelain", "-z"])?;
    Ok(output
        .split("\0\0")
        .filter_map(|record| {
            let mut path = None;
            let mut commit = String::new();
            let mut branch = None;
            let mut is_bare = false;
            for field in record.split('\0') {
                if let Some(value) = field.strip_prefix("worktree ") {
                    path = Some(PathBuf::from(value));
                } else if let Some(value) = field.strip_prefix("HEAD ") {
                    commit = value.to_owned();
                } else if let Some(value) = field.strip_prefix("branch refs/heads/") {
                    branch = Some(value.to_owned());
                } else if field == "bare" {
                    is_bare = true;
                }
            }
            Some(WorktreeSummary {
                path: path?,
                commit,
                branch,
                is_bare,
            })
        })
        .collect())
}

pub fn add_worktree(
    path: impl AsRef<Path>,
    destination: impl AsRef<Path>,
    branch: &str,
) -> Result<(), GajiError> {
    let root = root(path.as_ref())?;
    let branch = verify_branch(&root, branch)?;
    let destination = destination.as_ref().to_string_lossy();
    git(&root, &["worktree", "add", "--", &destination, &branch]).map(|_| ())
}

pub fn remove_worktree(
    path: impl AsRef<Path>,
    destination: impl AsRef<Path>,
    force: bool,
) -> Result<(), GajiError> {
    let root = root(path.as_ref())?;
    let destination = destination.as_ref().to_string_lossy();
    if force {
        git(
            &root,
            &["worktree", "remove", "--force", "--", &destination],
        )
    } else {
        git(&root, &["worktree", "remove", "--", &destination])
    }
    .map(|_| ())
}

pub fn submodules(path: impl AsRef<Path>) -> Result<Vec<SubmoduleSummary>, GajiError> {
    let root = root(path.as_ref())?;
    let output = git(&root, &["submodule", "status", "--recursive"])?;
    Ok(output
        .lines()
        .filter_map(|line| {
            let state = line.chars().next()?;
            let mut fields = line[1..].split_whitespace();
            Some(SubmoduleSummary {
                state,
                commit: fields.next()?.to_owned(),
                path: fields.next()?.to_owned(),
            })
        })
        .collect())
}

pub fn update_submodules(path: impl AsRef<Path>, initialize: bool) -> Result<(), GajiError> {
    let root = root(path.as_ref())?;
    if initialize {
        git(&root, &["submodule", "update", "--init", "--recursive"])
    } else {
        git(&root, &["submodule", "update", "--recursive"])
    }
    .map(|_| ())
}

pub fn initialize_repository(
    path: impl AsRef<Path>,
    default_branch: &str,
) -> Result<(), GajiError> {
    require_ref_name(default_branch)?;
    let destination = path.as_ref().to_string_lossy();
    git_process(&["init", "-b", default_branch, "--", &destination]).map(|_| ())
}

pub fn clone_repository(
    url: &str,
    destination: impl AsRef<Path>,
    bare: bool,
) -> Result<(), GajiError> {
    require_value("repository URL", url)?;
    let destination = destination.as_ref().to_string_lossy();
    if bare {
        git_process(&["clone", "--bare", "--", url, &destination])
    } else {
        git_process(&["clone", "--", url, &destination])
    }
    .map(|_| ())
}

pub fn search_history(path: impl AsRef<Path>, query: &str) -> Result<Vec<HistoryEntry>, GajiError> {
    require_value("search query", query)?;
    let root = root(path.as_ref())?;
    let output = git(
        &root,
        &[
            "log",
            "--all",
            "--regexp-ignore-case",
            "--date=iso-strict",
            &format!("--grep={query}"),
            "--pretty=format:%H%x1f%an%x1f%aI%x1f%s%x1e",
        ],
    )?;
    Ok(parse_history(&output))
}

pub fn commit_graph(path: impl AsRef<Path>, limit: usize) -> Result<Vec<GraphCommit>, GajiError> {
    commit_graph_page(path, 0, limit)
}

/// Returns one page of the topologically ordered commit graph.
///
/// `offset` is measured in visible graph commits, after Git's synthetic stash
/// helper commits have been removed. This makes adjacent pages safe to append.
pub fn commit_graph_page(
    path: impl AsRef<Path>,
    offset: usize,
    limit: usize,
) -> Result<Vec<GraphCommit>, GajiError> {
    let root = root(path.as_ref())?;
    let limit = limit.clamp(1, 10_000);
    let references = graph_references(&root)?;
    let head_exists = match git(&root, &["rev-parse", "--verify", "HEAD"]) {
        Ok(_) => true,
        Err(GajiError::GitFailed(_)) => false,
        Err(error) => return Err(error),
    };
    if references.is_empty() && !head_exists {
        return Ok(Vec::new());
    }

    let stash_helpers = stash_helper_commits(&root, &references)?;
    let helper_ids: HashSet<&str> = stash_helpers
        .values()
        .flatten()
        .map(String::as_str)
        .collect();
    let hidden_helper_ids: HashSet<&str> = helper_ids
        .iter()
        .copied()
        .filter(|id| references.get(*id).is_none_or(Vec::is_empty))
        .collect();
    let physical_offset = graph_physical_offset(&root, head_exists, offset, &hidden_helper_ids)?;
    // Git counts the synthetic index/untracked stash parents towards `-n`. Read
    // enough extra rows that removing those implementation details does not
    // unexpectedly shorten the requested graph.
    let log_limit = limit.saturating_add(hidden_helper_ids.len()).to_string();
    let skip = format!("--skip={physical_offset}");
    // Commit metadata may contain other control characters, but Git's normal
    // metadata inputs reject NULs. Use a NUL-delimited fixed six-field stream.
    let output = graph_log(
        &root,
        head_exists,
        &[
            "--date=iso-strict",
            "-z",
            "-n",
            &log_limit,
            &skip,
            "--pretty=format:%H%x00%P%x00%an%x00%ae%x00%aI%x00%s",
        ],
    )?;
    let mut fields = output.split('\0');
    let mut commits: Vec<_> = std::iter::from_fn(|| {
        let id = fields.next()?;
        if id.is_empty() {
            return None;
        }
        let parents = fields.next()?;
        let author = fields.next()?;
        let author_email = fields.next()?;
        let authored_at = fields.next()?;
        let subject = fields.next()?;
        let reference_details = references.get(id).cloned().unwrap_or_default();
        let is_stash = reference_details
            .iter()
            .any(|reference| reference.kind == GraphReferenceKind::Stash);
        Some(GraphCommit {
            id: id.to_owned(),
            parents: parents.split_whitespace().map(str::to_owned).collect(),
            references: reference_details
                .iter()
                .filter(|reference| !reference.is_suppressed)
                .map(graph_reference_label)
                .collect(),
            reference_details,
            kind: if is_stash {
                GraphCommitKind::Stash
            } else {
                GraphCommitKind::Commit
            },
            is_stash,
            author: author.to_owned(),
            author_email: author_email.to_owned(),
            authored_at: authored_at.to_owned(),
            subject: subject.to_owned(),
        })
    })
    .collect();

    for commit in &mut commits {
        if let Some(helpers) = stash_helpers.get(&commit.id) {
            commit.parents.truncate(1);
            debug_assert!(
                commit
                    .parents
                    .iter()
                    .all(|parent| !helpers.contains(parent))
            );
        }
    }
    commits.retain(|commit| {
        !helper_ids.contains(commit.id.as_str()) || !commit.reference_details.is_empty()
    });
    commits.truncate(limit);
    Ok(commits)
}

fn graph_physical_offset(
    root: &Path,
    head_exists: bool,
    visible_offset: usize,
    hidden_commit_ids: &HashSet<&str>,
) -> Result<usize, GajiError> {
    if visible_offset == 0 {
        return Ok(0);
    }

    // Only hashes are read for the skipped prefix. Decoding full metadata for
    // every preceding page would make later infinite-scroll loads increasingly
    // expensive. The extra rows account for every helper that can be hidden.
    let scan_limit = visible_offset
        .saturating_add(hidden_commit_ids.len())
        .to_string();
    let output = graph_log(
        root,
        head_exists,
        &["-n", &scan_limit, "--pretty=format:%H"],
    )?;
    let mut physical_offset = 0;
    let mut visible_count = 0;
    for id in output.lines().filter(|id| !id.is_empty()) {
        if visible_count == visible_offset {
            break;
        }
        physical_offset += 1;
        if !hidden_commit_ids.contains(id) {
            visible_count += 1;
        }
    }
    Ok(physical_offset)
}

fn graph_log(root: &Path, head_exists: bool, options: &[&str]) -> Result<String, GajiError> {
    let mut arguments = vec!["log", "--all", "--topo-order"];
    arguments.extend_from_slice(options);
    if head_exists {
        // `--all` follows refs, but a detached HEAD need not have one.
        arguments.push("HEAD");
    }
    git(root, &arguments)
}

fn graph_references(root: &Path) -> Result<HashMap<String, Vec<GraphReference>>, GajiError> {
    let current_ref = match git(root, &["symbolic-ref", "--quiet", "HEAD"]) {
        Ok(reference) => Some(reference.trim().to_owned()),
        Err(GajiError::GitFailed(_)) => None,
        Err(error) => return Err(error),
    };
    let output = git(
        root,
        &[
            "for-each-ref",
            "--format=%(objectname)%00%(*objectname)%00%(refname)%00%(upstream)%00%(symref)",
            "refs/heads",
            "refs/remotes",
            "refs/tags",
            "refs/stash",
        ],
    )?;
    let mut raw_references: Vec<_> = output
        .lines()
        .filter_map(|record| {
            let mut fields = record.splitn(5, '\0');
            let object = fields.next()?;
            let peeled = fields.next()?;
            let full_name = fields.next()?;
            let upstream = fields.next()?;
            let symbolic_target = fields.next()?;
            Some(RawGraphReference {
                object: if peeled.is_empty() { object } else { peeled }.to_owned(),
                full_name: full_name.to_owned(),
                upstream: upstream.to_owned(),
                symbolic_target: symbolic_target.to_owned(),
            })
        })
        .collect();

    if current_ref.is_none() {
        match git(root, &["rev-parse", "--verify", "HEAD"]) {
            Ok(head) => raw_references.push(RawGraphReference {
                object: head.trim().to_owned(),
                full_name: "HEAD".to_owned(),
                upstream: String::new(),
                symbolic_target: String::new(),
            }),
            Err(GajiError::GitFailed(_)) => {}
            Err(error) => return Err(error),
        }
    }

    let objects_by_ref: HashMap<_, _> = raw_references
        .iter()
        .map(|reference| (reference.full_name.as_str(), reference.object.as_str()))
        .collect();
    let mut suppressed = HashSet::new();
    for reference in &raw_references {
        if reference.full_name.starts_with("refs/heads/")
            && reference.upstream.starts_with("refs/remotes/")
            && objects_by_ref.get(reference.upstream.as_str()) == Some(&reference.object.as_str())
        {
            suppressed.insert(reference.upstream.as_str());
        }
        if reference.full_name.starts_with("refs/remotes/")
            && !reference.symbolic_target.is_empty()
            && objects_by_ref.get(reference.symbolic_target.as_str())
                == Some(&reference.object.as_str())
        {
            suppressed.insert(reference.full_name.as_str());
        }
    }

    let mut by_commit: HashMap<String, Vec<GraphReference>> = HashMap::new();
    for reference in &raw_references {
        let kind = graph_reference_kind(&reference.full_name);
        by_commit
            .entry(reference.object.clone())
            .or_default()
            .push(GraphReference {
                name: graph_reference_name(&reference.full_name).to_owned(),
                full_name: reference.full_name.clone(),
                kind,
                is_current: current_ref.as_deref() == Some(reference.full_name.as_str())
                    || kind == GraphReferenceKind::Head,
                is_suppressed: suppressed.contains(reference.full_name.as_str()),
            });
    }
    for references in by_commit.values_mut() {
        references.sort_by(|left, right| {
            graph_reference_sort_key(left)
                .cmp(&graph_reference_sort_key(right))
                .then_with(|| left.name.cmp(&right.name))
        });
    }
    Ok(by_commit)
}

fn stash_helper_commits(
    root: &Path,
    references: &HashMap<String, Vec<GraphReference>>,
) -> Result<HashMap<String, Vec<String>>, GajiError> {
    let mut stash_helpers = HashMap::new();
    for (commit, references) in references {
        if !references
            .iter()
            .any(|reference| reference.kind == GraphReferenceKind::Stash)
        {
            continue;
        }
        let output = git(root, &["show", "-s", "--format=%P", commit])?;
        let helpers = output
            .split_whitespace()
            .skip(1)
            .map(str::to_owned)
            .collect();
        stash_helpers.insert(commit.clone(), helpers);
    }
    Ok(stash_helpers)
}

fn graph_reference_kind(full_name: &str) -> GraphReferenceKind {
    if full_name == "HEAD" {
        GraphReferenceKind::Head
    } else if full_name.starts_with("refs/heads/") {
        GraphReferenceKind::LocalBranch
    } else if full_name.starts_with("refs/remotes/") {
        GraphReferenceKind::RemoteBranch
    } else if full_name.starts_with("refs/tags/") {
        GraphReferenceKind::Tag
    } else if full_name == "refs/stash" {
        GraphReferenceKind::Stash
    } else {
        GraphReferenceKind::Other
    }
}

fn graph_reference_name(full_name: &str) -> &str {
    full_name
        .strip_prefix("refs/heads/")
        .or_else(|| full_name.strip_prefix("refs/remotes/"))
        .or_else(|| full_name.strip_prefix("refs/tags/"))
        .unwrap_or(full_name)
}

fn graph_reference_sort_key(reference: &GraphReference) -> u8 {
    if reference.is_current {
        return 0;
    }
    match reference.kind {
        GraphReferenceKind::LocalBranch => 1,
        GraphReferenceKind::Tag => 2,
        GraphReferenceKind::RemoteBranch => 3,
        GraphReferenceKind::Stash => 4,
        GraphReferenceKind::Head => 0,
        GraphReferenceKind::Other => 5,
    }
}

fn graph_reference_label(reference: &GraphReference) -> String {
    match reference.kind {
        GraphReferenceKind::Head => "HEAD".to_owned(),
        GraphReferenceKind::LocalBranch if reference.is_current => {
            format!("HEAD -> {}", reference.name)
        }
        GraphReferenceKind::Tag => format!("tag: {}", reference.name),
        GraphReferenceKind::Stash | GraphReferenceKind::Other => reference.full_name.clone(),
        GraphReferenceKind::LocalBranch | GraphReferenceKind::RemoteBranch => {
            reference.name.clone()
        }
    }
}

struct RawGraphReference {
    object: String,
    full_name: String,
    upstream: String,
    symbolic_target: String,
}

pub fn commit_files(
    path: impl AsRef<Path>,
    commit: &str,
) -> Result<Vec<CommitFileChange>, GajiError> {
    require_value("commit", commit)?;
    let root = root(path.as_ref())?;
    let output = git(
        &root,
        &[
            "diff-tree",
            "--root",
            "--no-commit-id",
            "--name-status",
            "-r",
            "-M",
            commit,
        ],
    )?;
    Ok(output
        .lines()
        .filter_map(|line| {
            let fields: Vec<_> = line.split('\t').collect();
            let status = fields.first()?.to_string();
            let path = fields.last()?.to_string();
            Some(CommitFileChange { status, path })
        })
        .collect())
}

pub fn commit_file_diff(
    path: impl AsRef<Path>,
    commit: &str,
    file: &str,
) -> Result<String, GajiError> {
    require_value("commit", commit)?;
    require_value("file", file)?;
    let root = root(path.as_ref())?;
    git(
        &root,
        &["show", "--format=", "--find-renames", commit, "--", file],
    )
}

fn paths_command(path: &Path, prefix: &[&str], files: &[&str]) -> Result<(), GajiError> {
    if files.is_empty() {
        return Err(GajiError::GitFailed("no files selected".to_owned()));
    }
    let root = root(path)?;
    let mut arguments = prefix.to_vec();
    arguments.push("--");
    arguments.extend_from_slice(files);
    git(&root, &arguments).map(|_| ())
}

fn parse_count(value: &str) -> Option<u32> {
    value.parse().ok()
}

fn parse_hunks(patch: &str) -> Vec<DiffHunk> {
    let mut file_header = String::new();
    let mut current_header = String::new();
    let mut current_body = String::new();
    let mut hunks = Vec::new();

    for line in patch.split_inclusive('\n') {
        if line.starts_with("@@ ") {
            if !current_header.is_empty() {
                let id = hunks.len();
                hunks.push(DiffHunk {
                    id,
                    header: current_header.trim_end().to_owned(),
                    patch: format!("{file_header}{current_body}"),
                });
                current_body.clear();
            }
            current_header = line.trim_end().to_owned();
            current_body.push_str(line);
        } else if current_header.is_empty() {
            file_header.push_str(line);
        } else {
            current_body.push_str(line);
        }
    }
    if !current_header.is_empty() {
        let id = hunks.len();
        hunks.push(DiffHunk {
            id,
            header: current_header.trim_end().to_owned(),
            patch: format!("{file_header}{current_body}"),
        });
    }
    hunks
}

fn parse_history(output: &str) -> Vec<HistoryEntry> {
    output
        .split('\x1e')
        .filter_map(|record| {
            let mut fields = record.trim().splitn(4, '\x1f');
            Some(HistoryEntry {
                id: fields.next()?.to_owned(),
                author: fields.next()?.to_owned(),
                authored_at: fields.next()?.to_owned(),
                subject: fields.next()?.to_owned(),
            })
        })
        .collect()
}

fn git_process(arguments: &[&str]) -> Result<String, GajiError> {
    let output = Command::new("git")
        .args(arguments)
        .env("GIT_EDITOR", "true")
        .env("GIT_OPTIONAL_LOCKS", "0")
        .output()?;
    decode_output(output)
}

fn git_with_input(arguments: &[&str], input: &str) -> Result<String, GajiError> {
    let mut child = Command::new("git")
        .args(arguments)
        .env("GIT_OPTIONAL_LOCKS", "0")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()?;
    child
        .stdin
        .take()
        .expect("piped stdin")
        .write_all(input.as_bytes())?;
    decode_output(child.wait_with_output()?)
}

fn decode_output(output: std::process::Output) -> Result<String, GajiError> {
    if !output.status.success() {
        return Err(GajiError::GitFailed(
            String::from_utf8_lossy(&output.stderr).trim().to_owned(),
        ));
    }
    String::from_utf8(output.stdout).map_err(|_| GajiError::InvalidOutput)
}

fn root(path: &Path) -> Result<PathBuf, GajiError> {
    Ok(PathBuf::from(
        git(path, &["rev-parse", "--show-toplevel"])?.trim(),
    ))
}

fn resolve_commit(root: &Path, revision: &str) -> Result<String, GajiError> {
    require_value("revision", revision)?;
    git(
        root,
        &["rev-parse", "--verify", &format!("{revision}^{{commit}}")],
    )
    .map(|value| value.trim().to_owned())
}

fn verify_branch(root: &Path, branch: &str) -> Result<String, GajiError> {
    require_ref_name(branch)?;
    git(root, &["check-ref-format", "--branch", branch])?;
    git(
        root,
        &["show-ref", "--verify", &format!("refs/heads/{branch}")],
    )?;
    Ok(branch.to_owned())
}

fn require_ref_name(value: &str) -> Result<(), GajiError> {
    require_value("reference name", value)?;
    if value.starts_with('-') {
        return Err(GajiError::GitFailed(
            "reference names cannot start with '-'".to_owned(),
        ));
    }
    Ok(())
}

fn require_value(name: &str, value: &str) -> Result<(), GajiError> {
    if value.trim().is_empty() {
        Err(GajiError::GitFailed(format!("{name} cannot be empty")))
    } else {
        Ok(())
    }
}
