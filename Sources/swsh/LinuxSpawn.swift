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
      fdMap: FDMap,
      pathResolve: Bool
    ) -> SpawnResult {
        var cFdMap = [Int32]()
        for op in fdMap.createFdOperations() {
            switch op {
            case let .dup(src, dst):
                cFdMap.append(src)
                cFdMap.append(dst)
            case let .close(fd):
                cFdMap.append(-1)
                cFdMap.append(fd)
            }
        }

        let cCommand = command.withCString(strdup)
        var cArgs = [cCommand]
        cArgs.append(contentsOf: arguments.map { $0.withCString(strdup) })
        cArgs.append(nil)

        var env = env
        env["PATH"] = "\(env["PATH"] ?? "")\(ExternalCommand.supplementaryPath)"
        var cEnv = env.map { "\($0)=\($1)".withCString(strdup) }
        cEnv.append(nil)

        defer {
            cArgs.forEach { free($0) }
            cEnv.forEach { free($0) }
        }

        var pid = pid_t()
        let res = linuxSpawn.spawn(
            cCommand, cArgs, cEnv,
            UnsafeMutablePointer(mutating: cFdMap), cFdMap.count / 2,
            &pid
        )
        guard res == 0 else {
            return .error(errno: res)
        }
        let process = ProcessInformation(
            command: command, 
            arguments: arguments, 
            env: env, 
            id: pid
        )
        return .success(process)
    }

    public func reapAsync(
      process: ProcessInformation,
      queue: DispatchQueue,
      callback: @escaping (Int32) -> Void
    ) {
        Thread.detachNewThread {
            let status = spawnWait(process.id)
            queue.async {
                callback(status)
            }
        }
    }

    public func resume(
      process: ProcessInformation
    ) throws {
        kill(process.id, SIGCONT)
    }
}
#endif
