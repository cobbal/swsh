#if canImport(ucrt)

import ucrt
import Foundation
import windowsSpawn

/// A process spawned with `posix_spawn`
struct WindowsSpawn: ProcessSpawner {
    public func spawn(
      command: String,
      arguments: [String],
      env: [String: String],
      fdMap: FDMap,
      pathResolve: Bool
    ) -> SpawnResult {
      let intFDMap = Dictionary(uniqueKeysWithValues: fdMap.map { ($0.key.rawValue, $0.value.rawValue) })
      do {
        switch WindowsSpawnImpl.spawn(
          command: command,
          arguments: arguments,
          env: env,
          fdMap: intFDMap,
          pathResolve: pathResolve
        ) {
          case .success(let pid): return .success(pid)
          case .failure(let error): return .error(errno: error.errno)
        }
      }
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
