#if canImport(ucrt)

import ucrt
import Foundation
import windowsSpawn
import WinSDK

/// A process spawned with `posix_spawn`
struct WindowsSpawn: ProcessSpawner {
    public enum Error: Swift.Error {
      case systemError(String, DWORD)
    }

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

    static let windowsReapQueue = DispatchQueue(label: "TODO:remove_this_queue")

    public func reapAsync(
      pid: pid_t,
      queue: DispatchQueue,
      callback: @escaping (Int32) -> Void
    ) {
        //fatalError("TODO: reapAsync()")
        Self.windowsReapQueue.asyncAfter(deadline: .now() + 1.0) {
            callback(0)
        }
    }

    public func resume(
      pid: pid_t
    ) throws {
        let processHandle: HANDLE = OpenProcess(DWORD(bitPattern: THREAD_SUSPEND_RESUME), false, DWORD(pid))
        // guard processHandle != 0 else {
        //     let err = GetLastError()
        //     throw .failure(Error("Resuming process failed to find process: ", systemError: err))
        // }

        guard ResumeThread(processHandle) != DWORD(bitPattern: -1) else {
            let err = GetLastError()
            TerminateProcess(processHandle, 1)
            throw Error.systemError("Resuming process failed: ", err)
        }
    }
}

#endif
