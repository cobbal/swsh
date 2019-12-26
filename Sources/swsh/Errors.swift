import Foundation

/// Thrown when a string cannot be created with the requested encoding
public struct InvalidString: Error {
    /// The invalid data
    public let data: Data
    public let encoding: String.Encoding
}

/// Thrown when a string cannot be encoded with the requested incoding
public struct StringEncodingError: Error {
    public let string: String
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

/// A generic error from a syscall
public class SyscallError: Error, CommandResult, CustomStringConvertible {
    public let name: String
    public let error: Int32

    public let command: Command
    public var isRunning: Bool { false }
    public func exitCode() -> Int32 { -1 }

    init(name: String, command: Command, error: Int32) {
        self.name = name
        self.command = command
        self.error = error
    }

    public var description: String {
        "\(name) failed with error code \(error): \(String(cString: strerror(error)))"
    }

    public func succeed() throws {
        throw self
    }
}
