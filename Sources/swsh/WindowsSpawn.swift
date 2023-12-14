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
                case .success(let info): 
                    let process = ProcessInformation(
                        command: command,
                        arguments: arguments,
                        env: env,
                        id: Int(info.dwProcessId), 
                        handle: info.hProcess, 
                        mainThreadHandle: info.hThread
                    )
                    return .success(process)
                case .failure(let error): 
                    return .error(errno: error.errno)
            }
        }
    }

    public func reapAsync(
        process: ProcessInformation,
        queue: DispatchQueue,
        callback: @escaping (Int32) -> Void
    ) {
        queue.async {
          WaitForSingleObject(process.handle, INFINITE)
          
          var exitCode: DWORD = 0
          guard GetExitCodeProcess(process.handle, &exitCode) != false else {
              let err = GetLastError()
              print("\(process) reap failed with error: \(err)")
              callback(Int32(bitPattern: err)) // TODO: What should this be if the exit code cannot be determined?
              return
          }

          print("\(process) completed with exit code: \(exitCode)")
          callback(Int32(bitPattern: exitCode))
        }
    }

    public func resume(
        process: ProcessInformation
    ) throws {
        guard ResumeThread(process.mainThreadHandle) != DWORD(bitPattern: -1) else {
            let err = GetLastError()
            print("\(process) resume failed with error: \(err)")
            TerminateProcess(process.handle, 1)
            throw Error.systemError("Resuming process failed: ", err)
        }
    }
}

#endif
