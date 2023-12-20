import Foundation

#if canImport(Darwin)
import Darwin.C
#elseif canImport(Glibc)
import Glibc
#endif

/// Data used to identify a process
public struct ProcessInformation: CustomDebugStringConvertible {
    let command: String
    let arguments: [String]
    let env: [String: String]
    let id: pid_t
    let handle: UnsafeMutableRawPointer?
    let mainThreadHandle: UnsafeMutableRawPointer?
    
    public init(
        command: String, 
        arguments: [String], 
        env: [String: String], 
        id: pid_t, 
        handle: UnsafeMutableRawPointer? = nil, 
        mainThreadHandle: UnsafeMutableRawPointer? = nil) 
    {
        self.command = command
        self.arguments = arguments
        self.env = env
        self.id = id
        self.handle = handle
        self.mainThreadHandle = mainThreadHandle
    }

    public var debugDescription: String {
        return "\(id) \(command) \(arguments.joined(separator: " "))"
    }
}

/// The result of a spawn
public enum SpawnResult {
    /// A successful spawn with child process
    case success(ProcessInformation)
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
        process: ProcessInformation,
        queue: DispatchQueue,
        callback: @escaping (Int32) -> Void
    )

    func resume(
        process: ProcessInformation
    ) throws
}
