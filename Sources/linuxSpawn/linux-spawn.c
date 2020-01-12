#ifdef __linux__

#define _GNU_SOURCE
#include <unistd.h>
#include <signal.h>
#include <sys/wait.h>
#include <fcntl.h>
#include <stdio.h>
#include <errno.h>
#include <stdlib.h>
#include <strings.h>

#include "include/linux-spawn.h"

// I sometimes hate linux...
int spawn(pid_t *pidp,
          const char *file,
          char *const argv[],
          char *const envp[],
          int32_t *const fdMap,
          _Bool pathResolve)
{
    int fdlimit = (int)sysconf(_SC_OPEN_MAX);
    const int SRC = 1;
    const int DST = 2;
    uint8_t mentionedFds[fdlimit];
    bzero(mentionedFds, sizeof(mentionedFds));
    for (int32_t *p = fdMap; *p != -1; p += 2) {
        mentionedFds[p[0]] |= SRC;
        mentionedFds[p[1]] |= DST;
    }
    int pid;
    int pipeFds[2];
    // create a pipe so that the child can report to the parent on failure. If it's closed silently, it's a successful exec.
    if (pipe2(pipeFds, O_CLOEXEC) != 0) {
        return errno;
    }
    if (!(pid = fork())) {
        // make sure we aren't overwriting our pipe's fd by duping it
        int writePipe = -1;
        for (int i = 0; i < fdlimit; i++) {
            if (!mentionedFds[i]) {
                if (i == pipeFds[i]) {
                    // good fd, nothing to do
                    writePipe = i;
                } else if ((writePipe = dup3(pipeFds[1], i, O_CLOEXEC)) < 0) {
                    goto err;
                }
                break;
            }
        }
        if (writePipe < 0) {
            errno = EMFILE;
            goto err;
        }
        for (int32_t *p = fdMap; *p != -1; p += 2) {
            if (dup2(p[0], p[1]) < 0) {
                goto err;
            }
        }
        for (int i = 0; i < fdlimit; i++) {
            if (!(mentionedFds[i] & DST) && i != writePipe) {
                close(i);
            }
        }
        execvpe(file, argv, envp);
      err:;
        int err = errno;
        write(writePipe, &err, sizeof(err));
        exit(err);
    }
    close(pipeFds[1]);
    int ret = 0;
    if (pid < 0) {
        ret = pid;
    } else if (read(pipeFds[0], &ret, sizeof(ret)) == 0) {
        *pidp = pid;
    }
    close(pipeFds[0]);
    return ret;
}

int spawnWait(pid_t pid) {
    int status;
    do {
        waitpid(pid, &status, 0);
    } while (!WIFEXITED(status));
    return WEXITSTATUS(status);
}

#endif // __linux__
