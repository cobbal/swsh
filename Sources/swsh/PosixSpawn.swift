#if canImport(Darwin)

import Darwin.C
import Foundation

private let empty_file_actions: posix_spawn_file_actions_t? = nil
private let empty_spawnattrs: posix_spawnattr_t? = nil

/// A process spawned with `posix_spawn`
public struct PosixSpawn: ProcessSpawner {
    public func spawn(
      command: String,
      arguments: [String],
      env: [String: String],
      fdMap: Command.FDMap,
      pathResolve: Bool
    ) -> SpawnResult {
        var fileActions = empty_file_actions
        posix_spawn_file_actions_init(&fileActions)
        defer { posix_spawn_file_actions_destroy(&fileActions) }

        var attrs = empty_spawnattrs
        posix_spawnattr_init(&attrs)
        defer { posix_spawnattr_destroy(&attrs) }

        // Don't implicitly duplicate descriptors
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
            return .error(errno: res)
        }

        return .success(pid)
    }

    // C macros are unfortunately not bridged to swift, borrowed from Foundation/Process
    private static func WIFEXITED(_ status: Int32) -> Bool { return _WSTATUS(status) == 0 }
    private static func _WSTATUS(_ status: Int32) -> Int32 { return status & 0x7f }
    private static func WEXITSTATUS(_ status: Int32) -> Int32 { return (status >> 8) & 0xff }

    public func reapAsync(
      pid: pid_t,
      queue: DispatchQueue,
      callback: @escaping (Int32) -> Void
    ) {
        let processSource = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: queue)
        processSource.setEventHandler { [processSource] in
            var status: Int32 = 0
            waitpid(pid, &status, 0)
            if Self.WIFEXITED(status) {
                callback(PosixSpawn.WEXITSTATUS(status))
                processSource.cancel()
            }
        }
        processSource.activate()
    }
}

#endif
