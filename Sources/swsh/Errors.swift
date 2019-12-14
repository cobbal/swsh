import Foundation

/// Thrown when a string cannot be created with the requested encoding
public struct InvalidString: Error {
    /// The invalid data
    public let data: Data
    public let encoding: String.Encoding
}

/// An error thrown by some forms of running caused when the exit code of the child process is non-zero
public struct ExitCodeFailure: Error, CustomStringConvertible {
    /// The name of the process that failed
    public let name: String
    
    /// The exit code of the failed process
    public let exitCode: Int32
    
    public var description: String {
        "command \"\(name)\" failed with exit code \(exitCode)"
    }
}

/// An error thrown/returned when the system is unable to launch the requested process
public struct ProcessLaunchFailure: Error, CommandResult, CustomStringConvertible {
    let name: String
    /// The error code returned by the system
    public let error: Int32
    
    public var command: Command
    public var isRunning: Bool { false }
    public func exitCode() -> Int32 { error }
    
    init(command: ExternalCommand, error: Int32) {
        self.command = command
        self.name = command.command
        self.error = error
    }
    
    public var description: String {
        "failed to launch \"\(name)\" with error code \(error): \(String(cString: strerror(error)))"
    }
    
    public func succeed() throws {
        throw self
    }
}
