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
                case .success(let info): return .success(ProcessInformation(id: Int(info.dwProcessId), handle: info.hProcess, mainThreadHandle: info.hThread))
                case .failure(let error): return .error(errno: error.errno)
            }
        }
    }

    public func reapAsync(
        process: ProcessInformation,
        queue: DispatchQueue,
        callback: @escaping (Int32) -> Void
    ) {
        print("Windows Command Reaping...\n")
        queue.async {
          var exitCode: DWORD = 0
          guard GetExitCodeProcess(process.handle, &exitCode) != false else {
              let err = GetLastError()
              print("Windows Command Reap Failed with Error: \(err)\n")
              callback(Int32(bitPattern: err)) // TODO: What should this be if the exit code cannot be determined?
              return
          }
          guard exitCode != STILL_ACTIVE else {
              print("Windows Command Still Active. Requeuing reap.\n")
              queue.asyncAfter(deadline: .now() + 0.1) { reapAsync(process: process, queue: queue, callback: callback) }
              return
          }
          print("Windows Command Reaped with Exit Code: \(exitCode)\n")
          callback(Int32(bitPattern: exitCode))
        }
    }

    public func resume(
        process: ProcessInformation
    ) throws {
        print("Windows Command Resuming...\n")
        guard ResumeThread(process.mainThreadHandle) != DWORD(bitPattern: -1) else {
            print("Windows Command Resume Failed.\n")
            let err = GetLastError()
            TerminateProcess(process.handle, 1)
            throw Error.systemError("Resuming process failed: ", err)
        }
        print("Windows Command Resumed.\n")
    }
}

#endif
