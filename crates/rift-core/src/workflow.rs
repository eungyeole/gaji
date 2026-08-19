use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

use serde::Serialize;

use crate::{RiftError, git};

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

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct GraphCommit {
    pub id: String,
    pub parents: Vec<String>,
    pub references: Vec<String>,
    pub author: String,
    pub authored_at: String,
    pub subject: String,
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

pub fn diff_summary(path: impl AsRef<Path>, staged: bool) -> Result<Vec<DiffSummary>, RiftError> {
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

pub fn file_diff(path: impl AsRef<Path>, file: &str, staged: bool) -> Result<String, RiftError> {
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
) -> Result<Vec<DiffHunk>, RiftError> {
    let patch = file_diff(path, file, staged)?;
    Ok(parse_hunks(&patch))
}

pub fn apply_diff_patch(
    path: impl AsRef<Path>,
    patch: &str,
    staged: bool,
    reverse: bool,
) -> Result<(), RiftError> {
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

pub fn stage(path: impl AsRef<Path>, files: &[&str]) -> Result<(), RiftError> {
    paths_command(path.as_ref(), &["add"], files)
}

pub fn unstage(path: impl AsRef<Path>, files: &[&str]) -> Result<(), RiftError> {
    paths_command(path.as_ref(), &["restore", "--staged"], files)
}

pub fn discard(path: impl AsRef<Path>, files: &[&str]) -> Result<(), RiftError> {
    paths_command(path.as_ref(), &["restore", "--worktree"], files)
}

pub fn commit(path: impl AsRef<Path>, message: &str, amend: bool) -> Result<String, RiftError> {
    require_value("commit message", message)?;
    let root = root(path.as_ref())?;
    let output = if amend {
        git(&root, &["commit", "--amend", "-m", message])?
    } else {
        git(&root, &["commit", "-m", message])?
    };
    let _ = output;
    git(&root, &["rev-parse", "HEAD"]).map(|value| value.trim().to_owned())
}

pub fn branches(path: impl AsRef<Path>) -> Result<Vec<BranchSummary>, RiftError> {
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

pub fn switch_branch(path: impl AsRef<Path>, branch: &str) -> Result<(), RiftError> {
    let root = root(path.as_ref())?;
    let reference = verify_branch(&root, branch)?;
    git(&root, &["switch", &reference]).map(|_| ())
}

pub fn create_branch(
    path: impl AsRef<Path>,
    name: &str,
    start: &str,
    switch: bool,
) -> Result<(), RiftError> {
    require_ref_name(name)?;
    let root = root(path.as_ref())?;
    let commit = resolve_commit(&root, start)?;
    if switch {
        git(&root, &["switch", "-c", name, &commit])
    } else {
        git(&root, &["branch", name, &commit])
    }
    .map(|_| ())
}

pub fn delete_branch(path: impl AsRef<Path>, name: &str, force: bool) -> Result<(), RiftError> {
    let root = root(path.as_ref())?;
    let branch = verify_branch(&root, name)?;
    git(&root, &["branch", if force { "-D" } else { "-d" }, &branch]).map(|_| ())
}

pub fn rename_branch(path: impl AsRef<Path>, old: &str, new: &str) -> Result<(), RiftError> {
    require_ref_name(new)?;
    let root = root(path.as_ref())?;
    let old = verify_branch(&root, old)?;
    git(&root, &["branch", "-m", &old, new]).map(|_| ())
}

pub fn remotes(path: impl AsRef<Path>) -> Result<Vec<RemoteSummary>, RiftError> {
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

pub fn add_remote(path: impl AsRef<Path>, name: &str, url: &str) -> Result<(), RiftError> {
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
) -> Result<(), RiftError> {
    require_value("remote URL", url)?;
    let root = root(path.as_ref())?;
    if push {
        git(&root, &["remote", "set-url", "--push", name, url])
    } else {
        git(&root, &["remote", "set-url", name, url])
    }
    .map(|_| ())
}

pub fn remove_remote(path: impl AsRef<Path>, name: &str) -> Result<(), RiftError> {
    let root = root(path.as_ref())?;
    git(&root, &["remote", "remove", name]).map(|_| ())
}

pub fn fetch(path: impl AsRef<Path>, remote: &str, prune: bool) -> Result<(), RiftError> {
    let root = root(path.as_ref())?;
    if prune {
        git(&root, &["fetch", "--prune", "--", remote])
    } else {
        git(&root, &["fetch", "--", remote])
    }
    .map(|_| ())
}

pub fn pull(path: impl AsRef<Path>, rebase: bool) -> Result<(), RiftError> {
    let root = root(path.as_ref())?;
    git(
        &root,
        &["pull", if rebase { "--rebase" } else { "--no-rebase" }],
    )
    .map(|_| ())
}

pub fn push(
    path: impl AsRef<Path>,
    remote: &str,
    branch: &str,
    set_upstream: bool,
    force_with_lease: bool,
) -> Result<(), RiftError> {
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

pub fn stashes(path: impl AsRef<Path>) -> Result<Vec<StashSummary>, RiftError> {
    let root = root(path.as_ref())?;
    let output = git(&root, &["stash", "list", "--format=%gd%x00%s%x00"])?;
    let fields: Vec<&str> = output.split('\0').collect();
    Ok(fields
        .chunks(2)
        .enumerate()
        .filter_map(|(index, item)| {
            if item.len() < 2 || item[0].is_empty() {
                return None;
            }
            Some(StashSummary {
                index,
                reference: item[0].to_owned(),
                subject: item[1].to_owned(),
            })
        })
        .collect())
}

pub fn stash_push(
    path: impl AsRef<Path>,
    message: &str,
    include_untracked: bool,
) -> Result<(), RiftError> {
    let root = root(path.as_ref())?;
    if include_untracked {
        git(&root, &["stash", "push", "-u", "-m", message])
    } else {
        git(&root, &["stash", "push", "-m", message])
    }
    .map(|_| ())
}

pub fn stash_apply(path: impl AsRef<Path>, index: usize, pop: bool) -> Result<(), RiftError> {
    let root = root(path.as_ref())?;
    let reference = format!("stash@{{{index}}}");
    git(
        &root,
        &["stash", if pop { "pop" } else { "apply" }, &reference],
    )
    .map(|_| ())
}

pub fn stash_drop(path: impl AsRef<Path>, index: usize) -> Result<(), RiftError> {
    let root = root(path.as_ref())?;
    let reference = format!("stash@{{{index}}}");
    git(&root, &["stash", "drop", &reference]).map(|_| ())
}

pub fn tags(path: impl AsRef<Path>) -> Result<Vec<String>, RiftError> {
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
) -> Result<(), RiftError> {
    require_ref_name(name)?;
    let root = root(path.as_ref())?;
    let commit = resolve_commit(&root, target)?;
    match message {
        Some(message) => git(&root, &["tag", "-a", name, &commit, "-m", message]),
        None => git(&root, &["tag", name, &commit]),
    }
    .map(|_| ())
}

pub fn delete_tag(path: impl AsRef<Path>, name: &str) -> Result<(), RiftError> {
    let root = root(path.as_ref())?;
    git(&root, &["tag", "-d", "--", name]).map(|_| ())
}

pub fn push_tag(path: impl AsRef<Path>, remote: &str, name: &str) -> Result<(), RiftError> {
    require_ref_name(name)?;
    let root = root(path.as_ref())?;
    git(&root, &["push", "--", remote, &format!("refs/tags/{name}")]).map(|_| ())
}

pub fn reset(path: impl AsRef<Path>, target: &str, mode: ResetMode) -> Result<(), RiftError> {
    let root = root(path.as_ref())?;
    let commit = resolve_commit(&root, target)?;
    let mode = match mode {
        ResetMode::Soft => "--soft",
        ResetMode::Mixed => "--mixed",
        ResetMode::Hard => "--hard",
    };
    git(&root, &["reset", mode, &commit]).map(|_| ())
}

pub fn revert(path: impl AsRef<Path>, target: &str) -> Result<(), RiftError> {
    let root = root(path.as_ref())?;
    let commit = resolve_commit(&root, target)?;
    git(&root, &["revert", "--no-edit", &commit]).map(|_| ())
}

pub fn merge(
    path: impl AsRef<Path>,
    revision: &str,
    no_fast_forward: bool,
) -> Result<(), RiftError> {
    let root = root(path.as_ref())?;
    let commit = resolve_commit(&root, revision)?;
    if no_fast_forward {
        git(&root, &["merge", "--no-ff", "--no-edit", &commit])
    } else {
        git(&root, &["merge", "--no-edit", &commit])
    }
    .map(|_| ())
}

pub fn file_history(path: impl AsRef<Path>, file: &str) -> Result<Vec<HistoryEntry>, RiftError> {
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

pub fn blame(path: impl AsRef<Path>, file: &str) -> Result<Vec<BlameLine>, RiftError> {
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

pub fn worktrees(path: impl AsRef<Path>) -> Result<Vec<WorktreeSummary>, RiftError> {
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
) -> Result<(), RiftError> {
    let root = root(path.as_ref())?;
    let branch = verify_branch(&root, branch)?;
    let destination = destination.as_ref().to_string_lossy();
    git(&root, &["worktree", "add", "--", &destination, &branch]).map(|_| ())
}

pub fn remove_worktree(
    path: impl AsRef<Path>,
    destination: impl AsRef<Path>,
    force: bool,
) -> Result<(), RiftError> {
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

pub fn submodules(path: impl AsRef<Path>) -> Result<Vec<SubmoduleSummary>, RiftError> {
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

pub fn update_submodules(path: impl AsRef<Path>, initialize: bool) -> Result<(), RiftError> {
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
) -> Result<(), RiftError> {
    require_ref_name(default_branch)?;
    let destination = path.as_ref().to_string_lossy();
    git_process(&["init", "-b", default_branch, "--", &destination]).map(|_| ())
}

pub fn clone_repository(
    url: &str,
    destination: impl AsRef<Path>,
    bare: bool,
) -> Result<(), RiftError> {
    require_value("repository URL", url)?;
    let destination = destination.as_ref().to_string_lossy();
    if bare {
        git_process(&["clone", "--bare", "--", url, &destination])
    } else {
        git_process(&["clone", "--", url, &destination])
    }
    .map(|_| ())
}

pub fn search_history(path: impl AsRef<Path>, query: &str) -> Result<Vec<HistoryEntry>, RiftError> {
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

pub fn commit_graph(path: impl AsRef<Path>, limit: usize) -> Result<Vec<GraphCommit>, RiftError> {
    let root = root(path.as_ref())?;
    let limit = limit.clamp(1, 10_000).to_string();
    let output = git(
        &root,
        &[
            "log",
            "--all",
            "--topo-order",
            "--date=iso-strict",
            "-n",
            &limit,
            "--pretty=format:%H%x1f%P%x1f%D%x1f%an%x1f%aI%x1f%s%x1e",
        ],
    )?;
    Ok(output
        .split('\x1e')
        .filter_map(|record| {
            let mut fields = record.trim().splitn(6, '\x1f');
            Some(GraphCommit {
                id: fields.next()?.to_owned(),
                parents: fields
                    .next()?
                    .split_whitespace()
                    .map(str::to_owned)
                    .collect(),
                references: fields
                    .next()?
                    .split(',')
                    .map(str::trim)
                    .filter(|reference| !reference.is_empty())
                    .map(str::to_owned)
                    .collect(),
                author: fields.next()?.to_owned(),
                authored_at: fields.next()?.to_owned(),
                subject: fields.next()?.to_owned(),
            })
        })
        .collect())
}

fn paths_command(path: &Path, prefix: &[&str], files: &[&str]) -> Result<(), RiftError> {
    if files.is_empty() {
        return Err(RiftError::GitFailed("no files selected".to_owned()));
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

fn git_process(arguments: &[&str]) -> Result<String, RiftError> {
    let output = Command::new("git")
        .args(arguments)
        .env("GIT_EDITOR", "true")
        .output()?;
    decode_output(output)
}

fn git_with_input(arguments: &[&str], input: &str) -> Result<String, RiftError> {
    let mut child = Command::new("git")
        .args(arguments)
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

fn decode_output(output: std::process::Output) -> Result<String, RiftError> {
    if !output.status.success() {
        return Err(RiftError::GitFailed(
            String::from_utf8_lossy(&output.stderr).trim().to_owned(),
        ));
    }
    String::from_utf8(output.stdout).map_err(|_| RiftError::InvalidOutput)
}

fn root(path: &Path) -> Result<PathBuf, RiftError> {
    Ok(PathBuf::from(
        git(path, &["rev-parse", "--show-toplevel"])?.trim(),
    ))
}

fn resolve_commit(root: &Path, revision: &str) -> Result<String, RiftError> {
    require_value("revision", revision)?;
    git(
        root,
        &["rev-parse", "--verify", &format!("{revision}^{{commit}}")],
    )
    .map(|value| value.trim().to_owned())
}

fn verify_branch(root: &Path, branch: &str) -> Result<String, RiftError> {
    require_ref_name(branch)?;
    git(root, &["check-ref-format", "--branch", branch])?;
    git(
        root,
        &["show-ref", "--verify", &format!("refs/heads/{branch}")],
    )?;
    Ok(branch.to_owned())
}

fn require_ref_name(value: &str) -> Result<(), RiftError> {
    require_value("reference name", value)?;
    if value.starts_with('-') {
        return Err(RiftError::GitFailed(
            "reference names cannot start with '-'".to_owned(),
        ));
    }
    Ok(())
}

fn require_value(name: &str, value: &str) -> Result<(), RiftError> {
    if value.trim().is_empty() {
        Err(RiftError::GitFailed(format!("{name} cannot be empty")))
    } else {
        Ok(())
    }
}
