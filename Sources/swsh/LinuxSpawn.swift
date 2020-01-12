import Foundation

#if canImport(Glibc)
import Glibc
import linuxSpawn

/// A process spawned with something less nice than `posix_spawn`
public struct LinuxSpawn: ProcessSpawner {
    public func spawn(
      command: String,
      arguments: [String],
      env: [String: String],
      fdMap: Command.FDMap,
      pathResolve: Bool
    ) -> SpawnResult {
        var cFdMap = [Int32]()
        for (srcFd, dstFd) in fdMap {
            cFdMap.append(srcFd)
            cFdMap.append(dstFd)
        }
        cFdMap.append(-1)

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
        let res = linuxSpawn.spawn(cCommand, cArgs, cEnv, UnsafeMutablePointer(mutating: cFdMap), &pid)
        guard res == 0 else {
            return .error(errno: res)
        }
        return .success(pid)
    }

    public func reapAsync(
      pid: pid_t,
      queue: DispatchQueue,
      callback: @escaping (Int32) -> Void
    ) {
        Thread.detachNewThread {
            let status = spawnWait(pid)
            queue.async {
                callback(status)
            }
        }
    }
}
#endif
