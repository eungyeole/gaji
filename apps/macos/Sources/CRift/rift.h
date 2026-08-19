#ifndef RIFT_H
#define RIFT_H

#include <stdbool.h>
#include <stddef.h>

char *rift_inspect_json(const char *path);
char *rift_operation_state_json(const char *path);
char *rift_interactive_rebase_plan_json(const char *path, const char *upstream);
char *rift_conflict_content_json(const char *path, const char *file);
char *rift_commit_graph_json(const char *path, size_t limit);
char *rift_file_hunks_json(const char *path, const char *file, bool staged);
char *rift_execute_json(const char *request);
void rift_string_free(char *value);

#endif
