import Foundation

/// A simple wrapper around Int32
public struct FileDescriptor: RawRepresentable, ExpressibleByIntegerLiteral {
    public var rawValue: Int32

    /// Initialize from a raw Int32
    public init(_ value: Int32) { rawValue = value }
    public init(rawValue value: Int32) { rawValue = value }
    public init(integerLiteral value: Int32) { rawValue = value }

    /// Standard file descriptor for input
    public static var stdin: FileDescriptor = 0

    /// Standard file descriptor for output
    public static var stdout: FileDescriptor = 1

    /// Standard file descriptor for error
    public static var stderr: FileDescriptor = 2
}

extension FileDescriptor: Hashable, Equatable, CustomStringConvertible {
    public var description: String {
        rawValue.description
    }
}

extension FileHandle {
    /// The underlying FD number
    @available(Windows, unavailable)
    public var fd: FileDescriptor {
        FileDescriptor(fileDescriptor)
    }
}
