#ifndef RIFT_H
#define RIFT_H

#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Returned strings are UTF-8 JSON and must be released with rift_string_free. */
char *rift_inspect_json(const char *path);
char *rift_operation_state_json(const char *path);
char *rift_interactive_rebase_plan_json(const char *path, const char *upstream);
char *rift_conflict_content_json(const char *path, const char *file);
char *rift_commit_graph_json(const char *path, size_t limit);
char *rift_file_hunks_json(const char *path, const char *file, bool staged);
char *rift_file_diff_json(const char *path, const char *file, bool staged);
char *rift_blame_json(const char *path, const char *file);
char *rift_file_history_json(const char *path, const char *file);
char *rift_worktrees_json(const char *path);
char *rift_submodules_json(const char *path);
char *rift_stashes_json(const char *path);
char *rift_execute_json(const char *request);
void rift_string_free(char *value);

#ifdef __cplusplus
}
#endif

#endif
