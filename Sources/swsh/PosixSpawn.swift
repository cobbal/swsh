import Foundation

#if os(OSX)
import Darwin.C
#else
import Glibc
#warning("TODO: never been tested, probably broken")
#endif

public enum PosixSpawn {
    enum Result {
        case success(pid_t)
        case error(Int32)
    }

    /// low level code to spawn a process
    /// fdMap is a list of file descriptor remappings, src -> dst (can be equal)
    /// Note: all unmapped descriptors will be closed
    /// Returns pid of spawned process
    static func spawn(
      command: String,
      arguments: [String],
      env: [String: String],
      fdMap: Command.FDMap,
      pathResolve: Bool = true
    ) -> Result {
        var fileActions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&fileActions)
        defer { posix_spawn_file_actions_destroy(&fileActions) }

        var attrs: posix_spawnattr_t?
        posix_spawnattr_init(&attrs)
        defer { posix_spawnattr_destroy(&attrs) }

        // Don't implicitly dunplicate descriptors
        // Start suspended to avoid race condition with the handler setup
        posix_spawnattr_setflags(&attrs, Int16(POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_START_SUSPENDED))
        for (srcFd, dstFd) in fdMap {
            posix_spawn_file_actions_adddup2(&fileActions, srcFd, dstFd)
        }

        let cCommand = command.withCString(strdup)
        var cArgs = [cCommand]
        cArgs.append(contentsOf: arguments.map { $0.withCString(strdup) })
        cArgs.append(nil)

        var cEnv = env.map { "\($0)=\($1)".withCString(strdup) }
        cEnv.append(nil)

        defer {
            cArgs.forEach { free($0) }
            cEnv.forEach { free($0) }
        }

        var pid = pid_t()
        let spawn_fn = pathResolve ? posix_spawnp : posix_spawn
        let res = spawn_fn(&pid, cCommand, &fileActions, &attrs, cArgs, cEnv)
        guard res == 0 else {
            return .error(res)
        }

        return .success(pid)
    }
}
