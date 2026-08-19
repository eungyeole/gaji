#ifndef RIFT_H
#define RIFT_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Returned strings are UTF-8 JSON and must be released with rift_string_free. */
char *rift_inspect_json(const char *path);
char *rift_operation_state_json(const char *path);
char *rift_execute_json(const char *request);
void rift_string_free(char *value);

#ifdef __cplusplus
}
#endif

#endif
