#ifdef _WIN32

/* Path search and command quoting functions from libuv */
/* https://github.com/libuv/libuv/blob/00357f87328def30a32af82c841e5d1667a2a827/src/win/process.c#L151 */

#include "include/path.h"
#include <windows.h>
#include <assert.h>
#include <inttypes.h>

/* Macros to map libuv functions to stdlib counterparts */
#define uv__malloc(size) malloc(size)
#define uv__free(ptr) free(ptr)
#define uv_fatal_error(error, call) _exit(error)
#define alloca(size) _alloca(size)
#ifndef ssize_t
#define ssize_t intptr_t
#endif
#define UV_ENOMEM -1

/* Table of required environment variables */
typedef struct env_var {
  const WCHAR* const wide;
  const WCHAR* const wide_eq;
  const size_t len; /* including null or '=' */
} env_var_t;
#define E_V(str) { L##str, L##str L"=", sizeof(str) }
static const env_var_t required_vars[] = { /* keep me sorted */
  E_V("HOMEDRIVE"),
  E_V("HOMEPATH"),
  E_V("LOGONSERVER"),
  E_V("PATH"),
  E_V("SYSTEMDRIVE"),
  E_V("SYSTEMROOT"),
  E_V("TEMP"),
  E_V("USERDOMAIN"),
  E_V("USERNAME"),
  E_V("USERPROFILE"),
  E_V("WINDIR"),
};
#define ARRAY_SIZE(a) (sizeof(a) / sizeof((a)[0]))
#define ARRAY_END(a)  ((a) + ARRAY_SIZE(a))

/*
 * String helper functions
 */

 static int32_t uv__wtf8_decode1(const char** input) {
  uint32_t code_point;
  uint8_t b1;
  uint8_t b2;
  uint8_t b3;
  uint8_t b4;

  b1 = **input;
  if (b1 <= 0x7F)
    return b1; /* ASCII code point */
  if (b1 < 0xC2)
    return -1; /* invalid: continuation byte */
  code_point = b1;

  b2 = *++*input;
  if ((b2 & 0xC0) != 0x80)
    return -1; /* invalid: not a continuation byte */
  code_point = (code_point << 6) | (b2 & 0x3F);
  if (b1 <= 0xDF)
    return 0x7FF & code_point; /* two-byte character */

  b3 = *++*input;
  if ((b3 & 0xC0) != 0x80)
    return -1; /* invalid: not a continuation byte */
  code_point = (code_point << 6) | (b3 & 0x3F);
  if (b1 <= 0xEF)
    return 0xFFFF & code_point; /* three-byte character */

  b4 = *++*input;
  if ((b4 & 0xC0) != 0x80)
    return -1; /* invalid: not a continuation byte */
  code_point = (code_point << 6) | (b4 & 0x3F);
  if (b1 <= 0xF4) {
    code_point &= 0x1FFFFF;
    if (code_point <= 0x10FFFF)
      return code_point; /* four-byte character */
  }

  /* code point too large */
  return -1;
}

ssize_t uv_wtf8_length_as_utf16(const char* source_ptr) {
  size_t w_target_len = 0;
  int32_t code_point;

  do {
    code_point = uv__wtf8_decode1(&source_ptr);
    if (code_point < 0)
      return -1;
    if (code_point > 0xFFFF)
      w_target_len++;
    w_target_len++;
  } while (*source_ptr++);

  return w_target_len;
}

void uv_wtf8_to_utf16(const char* source_ptr,
                      uint16_t* w_target,
                      size_t w_target_len) {
  int32_t code_point;

  do {
    code_point = uv__wtf8_decode1(&source_ptr);
    /* uv_wtf8_length_as_utf16 should have been called and checked first. */
    assert(code_point >= 0);
    if (code_point > 0x10000) {
      assert(code_point < 0x10FFFF);
      *w_target++ = (((code_point - 0x10000) >> 10) + 0xD800);
      *w_target++ = ((code_point - 0x10000) & 0x3FF) + 0xDC00;
      w_target_len -= 2;
    } else {
      *w_target++ = code_point;
      w_target_len -= 1;
    }
  } while (*source_ptr++);

  (void)w_target_len;
  assert(w_target_len == 0);
}

/*
 * Path search functions
 */

/*
 * Helper function for search_path
 */
static WCHAR* search_path_join_test(const WCHAR* dir,
                                    size_t dir_len,
                                    const WCHAR* name,
                                    size_t name_len,
                                    const WCHAR* ext,
                                    size_t ext_len,
                                    const WCHAR* cwd,
                                    size_t cwd_len) {
  WCHAR *result, *result_pos;
  DWORD attrs;
  if (dir_len > 2 &&
      ((dir[0] == L'\\' || dir[0] == L'/') &&
       (dir[1] == L'\\' || dir[1] == L'/'))) {
    /* It's a UNC path so ignore cwd */
    cwd_len = 0;
  } else if (dir_len >= 1 && (dir[0] == L'/' || dir[0] == L'\\')) {
    /* It's a full path without drive letter, use cwd's drive letter only */
    cwd_len = 2;
  } else if (dir_len >= 2 && dir[1] == L':' &&
      (dir_len < 3 || (dir[2] != L'/' && dir[2] != L'\\'))) {
    /* It's a relative path with drive letter (ext.g. D:../some/file)
     * Replace drive letter in dir by full cwd if it points to the same drive,
     * otherwise use the dir only.
     */
    if (cwd_len < 2 || _wcsnicmp(cwd, dir, 2) != 0) {
      cwd_len = 0;
    } else {
      dir += 2;
      dir_len -= 2;
    }
  } else if (dir_len > 2 && dir[1] == L':') {
    /* It's an absolute path with drive letter
     * Don't use the cwd at all
     */
    cwd_len = 0;
  }

  /* Allocate buffer for output */
  result = result_pos = (WCHAR*)uv__malloc(sizeof(WCHAR) *
      (cwd_len + 1 + dir_len + 1 + name_len + 1 + ext_len + 1));

  /* Copy cwd */
  wcsncpy(result_pos, cwd, cwd_len);
  result_pos += cwd_len;

  /* Add a path separator if cwd didn't end with one */
  if (cwd_len && wcsrchr(L"\\/:", result_pos[-1]) == NULL) {
    result_pos[0] = L'\\';
    result_pos++;
  }

  /* Copy dir */
  wcsncpy(result_pos, dir, dir_len);
  result_pos += dir_len;

  /* Add a separator if the dir didn't end with one */
  if (dir_len && wcsrchr(L"\\/:", result_pos[-1]) == NULL) {
    result_pos[0] = L'\\';
    result_pos++;
  }

  /* Copy filename */
  wcsncpy(result_pos, name, name_len);
  result_pos += name_len;

  if (ext_len) {
    /* Add a dot if the filename didn't end with one */
    if (name_len && result_pos[-1] != '.') {
      result_pos[0] = L'.';
      result_pos++;
    }

    /* Copy extension */
    wcsncpy(result_pos, ext, ext_len);
    result_pos += ext_len;
  }

  /* Null terminator */
  result_pos[0] = L'\0';

  attrs = GetFileAttributesW(result);

  if (attrs != INVALID_FILE_ATTRIBUTES &&
      !(attrs & FILE_ATTRIBUTE_DIRECTORY)) {
    return result;
  }

  uv__free(result);
  return NULL;
}


/*
 * Helper function for search_path
 */
static WCHAR* path_search_walk_ext(const WCHAR *dir,
                                   size_t dir_len,
                                   const WCHAR *name,
                                   size_t name_len,
                                   WCHAR *cwd,
                                   size_t cwd_len,
                                   int name_has_ext) {
  WCHAR* result;

  /* If the name itself has a nonempty extension, try this extension first */
  if (name_has_ext) {
    result = search_path_join_test(dir, dir_len,
                                   name, name_len,
                                   L"", 0,
                                   cwd, cwd_len);
    if (result != NULL) {
      return result;
    }
  }

  /* Try .com extension */
  result = search_path_join_test(dir, dir_len,
                                 name, name_len,
                                 L"com", 3,
                                 cwd, cwd_len);
  if (result != NULL) {
    return result;
  }

  /* Try .exe extension */
  result = search_path_join_test(dir, dir_len,
                                 name, name_len,
                                 L"exe", 3,
                                 cwd, cwd_len);
  if (result != NULL) {
    return result;
  }

  return NULL;
}


/*
 * search_path searches the system path for an executable filename -
 * the windows API doesn't provide this as a standalone function nor as an
 * option to CreateProcess.
 *
 * It tries to return an absolute filename.
 *
 * Furthermore, it tries to follow the semantics that cmd.exe, with this
 * exception that PATHEXT environment variable isn't used. Since CreateProcess
 * can start only .com and .exe files, only those extensions are tried. This
 * behavior equals that of msvcrt's spawn functions.
 *
 * - Do not search the path if the filename already contains a path (either
 *   relative or absolute).
 *
 * - If there's really only a filename, check the current directory for file,
 *   then search all path directories.
 *
 * - If filename specified has *any* extension, search for the file with the
 *   specified extension first.
 *
 * - If the literal filename is not found in a directory, try *appending*
 *   (not replacing) .com first and then .exe.
 *
 * - The path variable may contain relative paths; relative paths are relative
 *   to the cwd.
 *
 * - Directories in path may or may not end with a trailing backslash.
 *
 * - CMD does not trim leading/trailing whitespace from path/pathex entries
 *   nor from the environment variables as a whole.
 *
 * - When cmd.exe cannot read a directory, it will just skip it and go on
 *   searching. However, unlike posix-y systems, it will happily try to run a
 *   file that is not readable/executable; if the spawn fails it will not
 *   continue searching.
 *
 * UNC path support: we are dealing with UNC paths in both the path and the
 * filename. This is a deviation from what cmd.exe does (it does not let you
 * start a program by specifying an UNC path on the command line) but this is
 * really a pointless restriction.
 *
 */
static WCHAR* search_path(const WCHAR *file,
                            WCHAR *cwd,
                            const WCHAR *path) {
  int file_has_dir;
  WCHAR* result = NULL;
  WCHAR *file_name_start;
  WCHAR *dot;
  const WCHAR *dir_start, *dir_end, *dir_path;
  size_t dir_len;
  int name_has_ext;

  size_t file_len = wcslen(file);
  size_t cwd_len = wcslen(cwd);

  /* If the caller supplies an empty filename,
   * we're not gonna return c:\windows\.exe -- GFY!
   */
  if (file_len == 0
      || (file_len == 1 && file[0] == L'.')) {
    return NULL;
  }

  /* Find the start of the filename so we can split the directory from the
   * name. */
  for (file_name_start = (WCHAR*)file + file_len;
       file_name_start > file
           && file_name_start[-1] != L'\\'
           && file_name_start[-1] != L'/'
           && file_name_start[-1] != L':';
       file_name_start--);

  file_has_dir = file_name_start != file;

  /* Check if the filename includes an extension */
  dot = wcschr(file_name_start, L'.');
  name_has_ext = (dot != NULL && dot[1] != L'\0');

  if (file_has_dir) {
    /* The file has a path inside, don't use path */
    result = path_search_walk_ext(
        file, file_name_start - file,
        file_name_start, file_len - (file_name_start - file),
        cwd, cwd_len,
        name_has_ext);

  } else {
    dir_end = path;

    if (NeedCurrentDirectoryForExePathW(L"")) {
      /* The file is really only a name; look in cwd first, then scan path */
      result = path_search_walk_ext(L"", 0,
                                    file, file_len,
                                    cwd, cwd_len,
                                    name_has_ext);
    }

    while (result == NULL) {
      if (dir_end == NULL || *dir_end == L'\0') {
        break;
      }

      /* Skip the separator that dir_end now points to */
      if (dir_end != path || *path == L';') {
        dir_end++;
      }

      /* Next slice starts just after where the previous one ended */
      dir_start = dir_end;

      /* If path is quoted, find quote end */
      if (*dir_start == L'"' || *dir_start == L'\'') {
        dir_end = wcschr(dir_start + 1, *dir_start);
        if (dir_end == NULL) {
          dir_end = wcschr(dir_start, L'\0');
        }
      }
      /* Slice until the next ; or \0 is found */
      dir_end = wcschr(dir_end, L';');
      if (dir_end == NULL) {
        dir_end = wcschr(dir_start, L'\0');
      }

      /* If the slice is zero-length, don't bother */
      if (dir_end - dir_start == 0) {
        continue;
      }

      dir_path = dir_start;
      dir_len = dir_end - dir_start;

      /* Adjust if the path is quoted. */
      if (dir_path[0] == '"' || dir_path[0] == '\'') {
        ++dir_path;
        --dir_len;
      }

      if (dir_path[dir_len - 1] == '"' || dir_path[dir_len - 1] == '\'') {
        --dir_len;
      }

      result = path_search_walk_ext(dir_path, dir_len,
                                    file, file_len,
                                    cwd, cwd_len,
                                    name_has_ext);
    }
  }

  return result;
}


/*
 * Quotes command line arguments
 * Returns a pointer to the end (next char to be written) of the buffer
 */
WCHAR* quote_cmd_arg(const WCHAR *source, WCHAR *target) {
  size_t len = wcslen(source);
  size_t i;
  int quote_hit;
  WCHAR* start;

  if (len == 0) {
    /* Need double quotation for empty argument */
    *(target++) = L'"';
    *(target++) = L'"';
    return target;
  }

  if (NULL == wcspbrk(source, L" \t\"")) {
    /* No quotation needed */
    wcsncpy(target, source, len);
    target += len;
    return target;
  }

  if (NULL == wcspbrk(source, L"\"\\")) {
    /*
     * No embedded double quotes or backlashes, so I can just wrap
     * quote marks around the whole thing.
     */
    *(target++) = L'"';
    wcsncpy(target, source, len);
    target += len;
    *(target++) = L'"';
    return target;
  }

  /*
   * Expected input/output:
   *   input : hello"world
   *   output: "hello\"world"
   *   input : hello""world
   *   output: "hello\"\"world"
   *   input : hello\world
   *   output: hello\world
   *   input : hello\\world
   *   output: hello\\world
   *   input : hello\"world
   *   output: "hello\\\"world"
   *   input : hello\\"world
   *   output: "hello\\\\\"world"
   *   input : hello world\
   *   output: "hello world\\"
   */

  *(target++) = L'"';
  start = target;
  quote_hit = 1;

  for (i = len; i > 0; --i) {
    *(target++) = source[i - 1];

    if (quote_hit && source[i - 1] == L'\\') {
      *(target++) = L'\\';
    } else if(source[i - 1] == L'"') {
      quote_hit = 1;
      *(target++) = L'\\';
    } else {
      quote_hit = 0;
    }
  }
  target[0] = L'\0';
  _wcsrev(start);
  *(target++) = L'"';
  return target;
}


int make_program_args(char** args, int verbatim_arguments, WCHAR** dst_ptr) {
  char** arg;
  WCHAR* dst = NULL;
  WCHAR* temp_buffer = NULL;
  size_t dst_len = 0;
  size_t temp_buffer_len = 0;
  WCHAR* pos;
  int arg_count = 0;
  int err = 0;

  /* Count the required size. */
  for (arg = args; *arg; arg++) {
    ssize_t arg_len;

    arg_len = uv_wtf8_length_as_utf16(*arg);
    if (arg_len < 0)
      return arg_len;

    dst_len += arg_len;

    if ((size_t) arg_len > temp_buffer_len)
      temp_buffer_len = arg_len;

    arg_count++;
  }

  /* Adjust for potential quotes. Also assume the worst-case scenario that
   * every character needs escaping, so we need twice as much space. */
  dst_len = dst_len * 2 + arg_count * 2;

  /* Allocate buffer for the final command line. */
  dst = uv__malloc(dst_len * sizeof(WCHAR));
  if (dst == NULL) {
    err = UV_ENOMEM;
    goto error;
  }

  /* Allocate temporary working buffer. */
  temp_buffer = uv__malloc(temp_buffer_len * sizeof(WCHAR));
  if (temp_buffer == NULL) {
    err = UV_ENOMEM;
    goto error;
  }

  pos = dst;
  for (arg = args; *arg; arg++) {
    ssize_t arg_len;

    /* Convert argument to wide char. */
    arg_len = uv_wtf8_length_as_utf16(*arg);
    assert(arg_len > 0);
    assert(temp_buffer_len >= (size_t) arg_len);
    uv_wtf8_to_utf16(*arg, temp_buffer, arg_len);

    if (verbatim_arguments) {
      /* Copy verbatim. */
      wcscpy(pos, temp_buffer);
      pos += arg_len - 1;
    } else {
      /* Quote/escape, if needed. */
      pos = quote_cmd_arg(temp_buffer, pos);
    }

    *pos++ = *(arg + 1) ? L' ' : L'\0';
    assert(pos <= dst + dst_len);
  }

  uv__free(temp_buffer);

  *dst_ptr = dst;
  return 0;

error:
  uv__free(dst);
  uv__free(temp_buffer);
  return err;
}


int env_strncmp(const wchar_t* a, int na, const wchar_t* b) {
  wchar_t* a_eq;
  wchar_t* b_eq;
  wchar_t* A;
  wchar_t* B;
  int nb;
  int r;

  if (na < 0) {
    a_eq = wcschr(a, L'=');
    assert(a_eq);
    na = (int)(long)(a_eq - a);
  } else {
    na--;
  }
  b_eq = wcschr(b, L'=');
  assert(b_eq);
  nb = b_eq - b;

  A = _alloca((na+1) * sizeof(wchar_t));
  B = _alloca((nb+1) * sizeof(wchar_t));

  r = LCMapStringW(LOCALE_INVARIANT, LCMAP_UPPERCASE, a, na, A, na);
  assert(r==na);
  A[na] = L'\0';
  r = LCMapStringW(LOCALE_INVARIANT, LCMAP_UPPERCASE, b, nb, B, nb);
  assert(r==nb);
  B[nb] = L'\0';

  for (;;) {
    wchar_t AA = *A++;
    wchar_t BB = *B++;
    if (AA < BB) {
      return -1;
    } else if (AA > BB) {
      return 1;
    } else if (!AA && !BB) {
      return 0;
    }
  }
}


static int qsort_wcscmp(const void *a, const void *b) {
  wchar_t* astr = *(wchar_t* const*)a;
  wchar_t* bstr = *(wchar_t* const*)b;
  return env_strncmp(astr, -1, bstr);
}


/*
 * The way windows takes environment variables is different than what C does;
 * Windows wants a contiguous block of null-terminated strings, terminated
 * with an additional null.
 *
 * Windows has a few "essential" environment variables. winsock will fail
 * to initialize if SYSTEMROOT is not defined; some APIs make reference to
 * TEMP. SYSTEMDRIVE is probably also important. We therefore ensure that
 * these get defined if the input environment block does not contain any
 * values for them.
 *
 * Also add variables known to Cygwin to be required for correct
 * subprocess operation in many cases:
 * https://github.com/Alexpux/Cygwin/blob/b266b04fbbd3a595f02ea149e4306d3ab9b1fe3d/winsup/cygwin/environ.cc#L955
 *
 */
int make_program_env(char* env_block[], WCHAR** dst_ptr) {
  WCHAR* dst;
  WCHAR* ptr;
  char** env;
  size_t env_len = 0;
  size_t len;
  size_t i;
  size_t var_size;
  size_t env_block_count = 1; /* 1 for null-terminator */
  WCHAR* dst_copy;
  WCHAR** ptr_copy;
  WCHAR** env_copy;
  size_t required_vars_value_len[ARRAY_SIZE(required_vars)];

  /* first pass: determine size in UTF-16 */
  for (env = env_block; *env; env++) {
    ssize_t len;
    if (strchr(*env, '=')) {
      len = uv_wtf8_length_as_utf16(*env);
      if (len < 0)
        return len;
      env_len += len;
      env_block_count++;
    }
  }

  /* second pass: copy to UTF-16 environment block */
  dst_copy = uv__malloc(env_len * sizeof(WCHAR));
  if (dst_copy == NULL && env_len > 0) {
    return UV_ENOMEM;
  }
  env_copy = _alloca(env_block_count * sizeof(WCHAR*));

  ptr = dst_copy;
  ptr_copy = env_copy;
  for (env = env_block; *env; env++) {
    ssize_t len;
    if (strchr(*env, '=')) {
      len = uv_wtf8_length_as_utf16(*env);
      assert(len > 0);
      assert((size_t) len <= env_len - (ptr - dst_copy));
      uv_wtf8_to_utf16(*env, ptr, len);
      *ptr_copy++ = ptr;
      ptr += len;
    }
  }
  *ptr_copy = NULL;
  assert(env_len == 0 || env_len == (size_t) (ptr - dst_copy));

  /* sort our (UTF-16) copy */
  qsort(env_copy, env_block_count-1, sizeof(wchar_t*), qsort_wcscmp);

  /* third pass: check for required variables */
  for (ptr_copy = env_copy, i = 0; i < ARRAY_SIZE(required_vars); ) {
    int cmp;
    if (!*ptr_copy) {
      cmp = -1;
    } else {
      cmp = env_strncmp(required_vars[i].wide_eq,
                        required_vars[i].len,
                        *ptr_copy);
    }
    if (cmp < 0) {
      /* missing required var */
      var_size = GetEnvironmentVariableW(required_vars[i].wide, NULL, 0);
      required_vars_value_len[i] = var_size;
      if (var_size != 0) {
        env_len += required_vars[i].len;
        env_len += var_size;
      }
      i++;
    } else {
      ptr_copy++;
      if (cmp == 0)
        i++;
    }
  }

  /* final pass: copy, in sort order, and inserting required variables */
  dst = uv__malloc((1+env_len) * sizeof(WCHAR));
  if (!dst) {
    uv__free(dst_copy);
    return UV_ENOMEM;
  }

  for (ptr = dst, ptr_copy = env_copy, i = 0;
       *ptr_copy || i < ARRAY_SIZE(required_vars);
       ptr += len) {
    int cmp;
    if (i >= ARRAY_SIZE(required_vars)) {
      cmp = 1;
    } else if (!*ptr_copy) {
      cmp = -1;
    } else {
      cmp = env_strncmp(required_vars[i].wide_eq,
                        required_vars[i].len,
                        *ptr_copy);
    }
    if (cmp < 0) {
      /* missing required var */
      len = required_vars_value_len[i];
      if (len) {
        wcscpy(ptr, required_vars[i].wide_eq);
        ptr += required_vars[i].len;
        var_size = GetEnvironmentVariableW(required_vars[i].wide,
                                           ptr,
                                           (int) (env_len - (ptr - dst)));
        if (var_size != (DWORD) (len - 1)) { /* TODO: handle race condition? */
          uv_fatal_error(GetLastError(), "GetEnvironmentVariableW");
        }
      }
      i++;
    } else {
      /* copy var from env_block */
      len = wcslen(*ptr_copy) + 1;
      wmemcpy(ptr, *ptr_copy, len);
      ptr_copy++;
      if (cmp == 0)
        i++;
    }
  }

  /* Terminate with an extra NULL. */
  assert(env_len == (size_t) (ptr - dst));
  *ptr = L'\0';

  uv__free(dst_copy);
  *dst_ptr = dst;
  return 0;
}

#endif
