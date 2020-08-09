import Foundation

#if canImport(Darwin)
import Darwin.C
#elseif canImport(Glibc)
import Glibc
#endif

/// The result of a spawn
public enum SpawnResult {
    /// A successful spawn with child process pid
    case success(pid_t)
    /// A failed spawn with error `errno`
    case error(errno: Int32)
}

/// The low-level interface to spawn a process
public protocol ProcessSpawner {
    /// Spawns a subprocess.
    /// - Note: all unmapped descriptors will be closed
    /// - Parameter command: process to spawn
    /// - Parameter arguments: arguments to pass
    /// - Parameter env: all environment variables for subprocess
    /// - Parameter fdMap: a list of file descriptor remappings, src -> dst (can be equal)
    /// - Parameter pathResolve: if true, search for executable in PATH
    /// - Returns: pid of spawned process or error if failed
    func spawn(
      command: String,
      arguments: [String],
      env: [String: String],
      fdMap: FDMap,
      pathResolve: Bool
    ) -> SpawnResult

    /// Add a callback for child process exiting
    /// - Parameter pid: pid of child process
    /// - Parameter callback: called with exit code when child exits
    /// - Parameter queue: queue the callback is executed on
    func reapAsync(
      pid: pid_t,
      queue: DispatchQueue,
      callback: @escaping (Int32) -> Void
    )
}
