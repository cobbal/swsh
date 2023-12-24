#ifdef _WIN32

/* Path search and command quoting functions from libuv */
/* https://github.com/libuv/libuv/blob/00357f87328def30a32af82c841e5d1667a2a827/src/win/process.c#L151 */

#include <wchar.h>

wchar_t* search_path(const wchar_t *file, wchar_t *cwd, const wchar_t *path);
int make_program_args(char** args, int verbatim_arguments, wchar_t** dst_ptr);
int make_program_env(char* env_block[], wchar_t** dst_ptr);

#endif
