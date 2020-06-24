import Foundation

/// Thrown when a string cannot be created with the requested encoding
public struct InvalidString: Error {
    /// The invalid data
    public let data: Data
    /// The encoding used
    public let encoding: String.Encoding
}

/// Thrown when a string cannot be encoded with the requested incoding
public struct StringEncodingError: Error {
    /// The invalid string
    public let string: String
    /// The encoding used
    public let encoding: String.Encoding
}

/// An error thrown by some forms of running caused when the exit code of the child process is non-zero
public struct ExitCodeFailure: Error, CustomStringConvertible {
    /// The name of the process that failed
    public let name: String

    /// The exit code of the failed process
    public let exitCode: Int32

    public var description: String {
        return "command \"\(name)\" failed with exit code \(exitCode)"
    }
}

/// A generic error from a syscall
public class SyscallError: Error, CommandResult, CustomStringConvertible {
    /// A short description of the operation that generated the error
    public let name: String

    /// The errno set by the failing instruction
    public let errno: Int32

    public let command: Command
    public var isRunning: Bool { return false }
    public func exitCode() -> Int32 { return -1 }

    init(name: String, command: Command, errno: Int32) {
        self.name = name
        self.command = command
        self.errno = errno
    }

    public var description: String {
        return "\(name) failed with error code \(errno): \(String(cString: strerror(errno)))"
    }

    public func succeed() throws {
        throw self
    }

    public func kill(signal: Int32) throws {
        throw self
    }
}
