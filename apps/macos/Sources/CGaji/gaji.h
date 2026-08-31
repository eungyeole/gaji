#ifndef GAJI_H
#define GAJI_H

#include <stdbool.h>
#include <stddef.h>

char *gaji_inspect_json(const char *path);
char *gaji_operation_state_json(const char *path);
char *gaji_interactive_rebase_plan_json(const char *path, const char *upstream);
char *gaji_conflict_content_json(const char *path, const char *file);
char *gaji_commit_graph_json(const char *path, size_t limit);
char *gaji_commit_graph_page_json(const char *path, size_t offset, size_t limit);
char *gaji_commit_files_json(const char *path, const char *commit);
char *gaji_commit_file_diff_json(const char *path, const char *commit, const char *file);
char *gaji_file_hunks_json(const char *path, const char *file, bool staged);
char *gaji_file_diff_json(const char *path, const char *file, bool staged);
char *gaji_blame_json(const char *path, const char *file);
char *gaji_file_history_json(const char *path, const char *file);
char *gaji_worktrees_json(const char *path);
char *gaji_submodules_json(const char *path);
char *gaji_stashes_json(const char *path);
char *gaji_stash_files_json(const char *path, size_t index);
char *gaji_stash_file_diff_json(const char *path, size_t index, const char *file);
char *gaji_execute_json(const char *request);
void gaji_string_free(char *value);

#endif
