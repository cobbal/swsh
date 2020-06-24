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

/// spawn a process in a similar manner to posix_spawn using options
/// POSIX_SPAWN_CLOEXEC_DEFAULT and POSIX_SPAWN_START_SUSPENDED, neither of
/// which are available on linux.
///  - Parameter command: name of executable. Either the path to an executable,
///    or will be looked up in PATH. (Passed directly to `execvpe`)
///  - Parameter argv: null terminated list of arguments to pass to command.
///    (Passed directly to `execvpe`)
///  - Parameter envp: null terminated list of all environment variables to pass
///    to command. (Passed directly to `execvpe`)
///  - Parameter fdMap: a list of mappings from parent FDs to be inherited by child
///    FDs. Any FD not listed as a dst will be closed for the child. The list
///    must be -1 terminated, and in the format:
///    `{ src_0, dst_0, src_1, dst_1, ..., src_n, dst_n, -1 }`
///  - Returns: 0 if successful, an error code if an operation failed.
///  - Parameter child_pid_out: non-null, pid of child process will be written
///    to this pointer if successful.
int spawn(
    const char *command,
    char *const argv[],
    char *const envp[],
    const int32_t *fdMap,
    pid_t *child_pid_out
) {
    // First, create a table for fast lookup if an FD is a source and/or a
    // destination for dup
    long fdlimit = sysconf(_SC_OPEN_MAX);
    const uint8_t SRC = 1;
    const uint8_t DST = 2;
    uint8_t *mentionedFds = calloc(fdlimit, sizeof(uint8_t));
    for (const int32_t *p = fdMap; *p != -1; p += 2) {
        mentionedFds[p[0]] |= SRC;
        mentionedFds[p[1]] |= DST;
    }

    int pid;
    int pipeFds[2];
    // create a pipe so that the child can report to the parent on failure. If
    // it's closed silently, it's a successful exec. If not, it will send an
    // error code.
    if (pipe2(pipeFds, O_CLOEXEC) != 0) {
        free(mentionedFds);
        return errno;
    }

    if (!(pid = fork())) {
        // In child process. Prepare state for exec.

        // Find an FD to store our pipe in that won't interfere with fdMap
        int writePipe = -1;
        for (long i = 0; i < fdlimit; i++) {
            if (!mentionedFds[i]) {
                if (i == pipeFds[i]) {
                    // pipe picked a good fd, nothing to do
                    writePipe = i;
                } else if ((writePipe = dup3(pipeFds[1], i, O_CLOEXEC)) < 0) {
                    goto err;
                }
                break;
            }
        }
        if (writePipe < 0) {
            // All file descriptors seem to be in use, not one to spare for some
            // bookkeeping :(
            errno = EMFILE;
            goto err;
        }
        // do the actual fd remapping
        for (const int32_t *p = fdMap; *p != -1; p += 2) {
            if (dup2(p[0], p[1]) < 0) {
                goto err;
            }
        }
        for (int i = 0; i < fdlimit; i++) {
            // close all the FDs we don't need, even ones that aren't open
            // (faster than checking which ones are open I read somewhere on the
            // internet)
            if (!(mentionedFds[i] & DST) && i != writePipe) {
                close(i);
            }
        }
        // All good! If this returns, exec failed with an error.
        execvpe(command, argv, envp);
      err:;
        int err = errno;
        write(writePipe, &err, sizeof(err));
        exit(err);
    }
    // parent code

    // close our copy of the pipe's write end
    close(pipeFds[1]);
    int ret = 0;
    if (pid < 0) {
        // fork failed
        ret = pid;
    } else if (read(pipeFds[0], &ret, sizeof(ret)) == 0) {
        // pipe was closed silently, fork and exec succeeded
        *child_pid_out = pid;
    }
    close(pipeFds[0]);
    free(mentionedFds);
    return ret;
}

int spawnWait(pid_t pid) {
    int status;
    while (true) {
        waitpid(pid, &status, 0);
        if WIFEXITED(status) {
            return WEXITSTATUS(status);
        } else if WIFSIGNALED(status) {
            return 1;
        }
    }
}

#endif // __linux__
