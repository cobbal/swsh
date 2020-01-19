#ifdef __linux__

#include <stdint.h>
#include <termios.h>

int spawn(
    const char *command,
    char *const argv[],
    char *const envp[],
    const int32_t *fdMap,
    pid_t *child_pid_out
);

int spawnWait(pid_t pid);

#endif // __linux__
