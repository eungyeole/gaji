use std::env;

use anyhow::{Context, Result, bail};
use rift_core::ConflictSide;

fn main() -> Result<()> {
    let arguments: Vec<String> = env::args().skip(1).collect();
    if arguments.is_empty() {
        return inspect(".");
    }

    match arguments[0].as_str() {
        "inspect" => inspect(arguments.get(1).map(String::as_str).unwrap_or("."))?,
        "operation" => {
            let path = arguments.get(1).map(String::as_str).unwrap_or(".");
            let state = rift_core::operation_state(path)?;
            println!("{}", serde_json::to_string_pretty(&state)?);
        }
        "cherry-pick" => {
            let (path, revision) = two_arguments(&arguments, "cherry-pick <path> <revision>")?;
            rift_core::cherry_pick(path, revision)?;
        }
        "rebase" => {
            let (path, upstream) = two_arguments(&arguments, "rebase <path> <upstream>")?;
            rift_core::rebase_onto(path, upstream)?;
        }
        "continue" => rift_core::continue_operation(one_path(&arguments))?,
        "abort" => rift_core::abort_operation(one_path(&arguments))?,
        "resolve" => {
            let path = arguments
                .get(1)
                .context("resolve <path> <file> [ours|theirs|manual]")?;
            let file = arguments
                .get(2)
                .context("resolve <path> <file> [ours|theirs|manual]")?;
            match arguments.get(3).map(String::as_str).unwrap_or("manual") {
                "ours" => rift_core::choose_conflict_side(path, file, ConflictSide::Ours)?,
                "theirs" => rift_core::choose_conflict_side(path, file, ConflictSide::Theirs)?,
                "manual" => rift_core::mark_resolved(path, file)?,
                value => bail!("unknown resolution strategy: {value}"),
            }
        }
        path => inspect(path)?,
    }
    Ok(())
}

fn inspect(path: &str) -> Result<()> {
    let snapshot = rift_core::inspect_repository(path)
        .with_context(|| format!("failed to inspect repository at {path}"))?;
    println!("{}", serde_json::to_string_pretty(&snapshot)?);
    Ok(())
}

fn one_path(arguments: &[String]) -> &str {
    arguments.get(1).map(String::as_str).unwrap_or(".")
}

fn two_arguments<'a>(arguments: &'a [String], usage: &str) -> Result<(&'a str, &'a str)> {
    let path = arguments.get(1).with_context(|| usage.to_owned())?;
    let value = arguments.get(2).with_context(|| usage.to_owned())?;
    Ok((path, value))
}
