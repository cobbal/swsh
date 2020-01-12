#include <stdint.h>
#include <termios.h>

int spawn(pid_t *pid,
          const char *file,
          char *const argv[], // NULL terminated
          char *const envp[], // NULL terminated
          int32_t *const fdMap,  // -1 terminated
          _Bool pathResolve);

int spawnWait(pid_t pid);
