use std::ffi::{CStr, CString, c_char};
use std::path::Path;

use serde::{Deserialize, Serialize};

#[derive(Debug, Deserialize)]
#[serde(tag = "action", rename_all = "camelCase")]
enum Request {
    Stage {
        path: String,
        files: Vec<String>,
    },
    Unstage {
        path: String,
        files: Vec<String>,
    },
    Discard {
        path: String,
        files: Vec<String>,
    },
    Commit {
        path: String,
        message: String,
        amend: bool,
    },
    CherryPick {
        path: String,
        revision: String,
    },
    Rebase {
        path: String,
        upstream: String,
    },
    Merge {
        path: String,
        revision: String,
        no_fast_forward: bool,
    },
    Continue {
        path: String,
    },
    Abort {
        path: String,
    },
    Resolve {
        path: String,
        file: String,
        side: Option<Side>,
    },
    StashPush {
        path: String,
        message: String,
        include_untracked: bool,
    },
    StashApply {
        path: String,
        index: usize,
        pop: bool,
    },
    StashDrop {
        path: String,
        index: usize,
    },
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
enum Side {
    Ours,
    Theirs,
}

enum FileOperation {
    Stage,
    Unstage,
    Discard,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct Response<T: Serialize> {
    ok: bool,
    value: Option<T>,
    error: Option<String>,
}

#[unsafe(no_mangle)]
/// Inspects a repository and returns an owned UTF-8 JSON string.
///
/// # Safety
/// `path` must be null or point to a valid, NUL-terminated C string. The return
/// value must be released exactly once with [`rift_string_free`].
pub unsafe extern "C" fn rift_inspect_json(path: *const c_char) -> *mut c_char {
    respond(|| {
        let path = unsafe { required_string(path, "path")? };
        rift_core::inspect_repository(path).map_err(|error| error.to_string())
    })
}

#[unsafe(no_mangle)]
/// Reads the current sequencer/conflict state as an owned UTF-8 JSON string.
///
/// # Safety
/// `path` must be null or point to a valid, NUL-terminated C string. The return
/// value must be released exactly once with [`rift_string_free`].
pub unsafe extern "C" fn rift_operation_state_json(path: *const c_char) -> *mut c_char {
    respond(|| {
        let path = unsafe { required_string(path, "path")? };
        rift_core::operation_state(path).map_err(|error| error.to_string())
    })
}

#[unsafe(no_mangle)]
/// Executes a JSON-encoded request and returns an owned UTF-8 JSON response.
///
/// # Safety
/// `request` must be null or point to a valid, NUL-terminated C string. The
/// return value must be released exactly once with [`rift_string_free`].
pub unsafe extern "C" fn rift_execute_json(request: *const c_char) -> *mut c_char {
    respond(|| {
        let request = unsafe { required_string(request, "request")? };
        let request: Request = serde_json::from_str(&request).map_err(|error| error.to_string())?;
        execute(request)?;
        Ok(())
    })
}

#[unsafe(no_mangle)]
/// Releases a string returned by this library.
///
/// # Safety
/// `value` must be null or a live pointer returned by a Rift FFI function. It
/// must not be freed more than once or used after this call.
pub unsafe extern "C" fn rift_string_free(value: *mut c_char) {
    if !value.is_null() {
        drop(unsafe { CString::from_raw(value) });
    }
}

fn execute(request: Request) -> Result<(), String> {
    match request {
        Request::Stage { path, files } => with_files(&path, &files, FileOperation::Stage),
        Request::Unstage { path, files } => with_files(&path, &files, FileOperation::Unstage),
        Request::Discard { path, files } => with_files(&path, &files, FileOperation::Discard),
        Request::Commit {
            path,
            message,
            amend,
        } => rift_core::commit(path, &message, amend).map(|_| ()),
        Request::CherryPick { path, revision } => rift_core::cherry_pick(path, &revision),
        Request::Rebase { path, upstream } => rift_core::rebase_onto(path, &upstream),
        Request::Merge {
            path,
            revision,
            no_fast_forward,
        } => rift_core::merge(path, &revision, no_fast_forward),
        Request::Continue { path } => rift_core::continue_operation(path),
        Request::Abort { path } => rift_core::abort_operation(path),
        Request::Resolve { path, file, side } => match side {
            Some(Side::Ours) => {
                rift_core::choose_conflict_side(path, &file, rift_core::ConflictSide::Ours)
            }
            Some(Side::Theirs) => {
                rift_core::choose_conflict_side(path, &file, rift_core::ConflictSide::Theirs)
            }
            None => rift_core::mark_resolved(path, &file),
        },
        Request::StashPush {
            path,
            message,
            include_untracked,
        } => rift_core::stash_push(path, &message, include_untracked),
        Request::StashApply { path, index, pop } => rift_core::stash_apply(path, index, pop),
        Request::StashDrop { path, index } => rift_core::stash_drop(path, index),
    }
    .map_err(|error| error.to_string())
}

fn with_files(
    path: &str,
    files: &[String],
    operation: FileOperation,
) -> Result<(), rift_core::RiftError> {
    let files: Vec<&str> = files.iter().map(String::as_str).collect();
    match operation {
        FileOperation::Stage => rift_core::stage(Path::new(path), &files),
        FileOperation::Unstage => rift_core::unstage(Path::new(path), &files),
        FileOperation::Discard => rift_core::discard(Path::new(path), &files),
    }
}

fn respond<T, F>(operation: F) -> *mut c_char
where
    T: Serialize,
    F: FnOnce() -> Result<T, String>,
{
    let response = match operation() {
        Ok(value) => Response {
            ok: true,
            value: Some(value),
            error: None,
        },
        Err(error) => Response {
            ok: false,
            value: None,
            error: Some(error),
        },
    };
    let json = serde_json::to_string(&response)
        .unwrap_or_else(|_| "{\"ok\":false,\"error\":\"serialization failed\"}".to_owned());
    CString::new(json)
        .expect("JSON cannot contain NUL")
        .into_raw()
}

unsafe fn required_string(value: *const c_char, name: &str) -> Result<String, String> {
    if value.is_null() {
        return Err(format!("{name} is required"));
    }
    unsafe { CStr::from_ptr(value) }
        .to_str()
        .map(str::to_owned)
        .map_err(|_| format!("{name} must be UTF-8"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn returns_owned_json_across_the_ffi_boundary() {
        let repository = CString::new(env!("CARGO_MANIFEST_DIR")).unwrap();
        let pointer = unsafe { rift_inspect_json(repository.as_ptr()) };
        assert!(!pointer.is_null());
        let json = unsafe { CStr::from_ptr(pointer) }.to_str().unwrap();
        let response: serde_json::Value = serde_json::from_str(json).unwrap();
        assert_eq!(response["ok"], true);
        assert!(
            response["value"]["root"]
                .as_str()
                .unwrap()
                .ends_with("/rift")
        );
        unsafe { rift_string_free(pointer) };
    }
}
