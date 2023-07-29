#if canImport(ucrt)

import ucrt
import Foundation

/// A process spawned with `posix_spawn`
public struct WindowsSpawn: ProcessSpawner {
    public func spawn(
      command: String,
      arguments: [String],
      env: [String: String],
      fdMap: FDMap,
      pathResolve: Bool
    ) -> SpawnResult {
        fatalError("TODO")
    }

    public func reapAsync(
      pid: pid_t,
      queue: DispatchQueue,
      callback: @escaping (Int32) -> Void
    ) {
        fatalError("TODO")
    }

    public func resume(
      pid: pid_t
    ) throws {
        fatalError("TODO")
    }
}

#endif
