import Foundation

#if os(Windows)
import ucrt
#endif

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
        "command \"\(name)\" failed with exit code \(exitCode)"
    }
}

/// A generic error from a syscall
public class SyscallError: Error, CommandResult, CustomStringConvertible {
    /// A short description of the operation that generated the error
    public let name: String

    /// The errno set by the failing instruction
    public let errno: Int32

    public let command: Command
    public var isRunning: Bool { false }
    public func exitCode() -> Int32 { -1 }

    init(name: String, command: Command, errno: Int32) {
        self.name = name
        self.command = command
        self.errno = errno
    }

    public var description: String {
        let errorMessage: String
        #if os(Windows)
        let errlen = 1024 // Is this enough? Windows is badly designed and poorly documented
        errorMessage = withUnsafeTemporaryAllocation(of: CChar.self, capacity: errlen + 1) { buffer in
            strerror_s(buffer.baseAddress, errlen, errno)
            // Ensure we have at least 1 null terminator, not sure if this is needed
            buffer[errlen] = 0
            return String(cString: buffer.baseAddress!)
        }
        #else
        errorMessage = String(cString: strerror(errno))
        #endif
        return "\(name) failed with error code \(errno): \(errorMessage)"
    }

    public func succeed() throws {
        throw self
    }

    public func _kill(signal: Int32) throws {
        throw self
    }
}

enum PlatformError: Error {
    case killUnsupportedOnWindows
}