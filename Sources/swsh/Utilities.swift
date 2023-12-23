import Foundation

infix operator ??= : AssignmentPrecedence
func ??= <Wrapped>(lhs: inout Wrapped?, rhs: @autoclosure () -> Wrapped) {
    lhs = lhs ?? rhs()
}

/// Thrown when changing directory fails. Could be because directory doesn't exist, or permissions prevent it.
public struct ChangeDirectoryFailedError: Error {}

extension FileManager {
    /// Change current directory to `path` for the duration of `body`, then return to previous directory.
    /// - Throws: `ChangeDirectoryFailedError` if directory change fails, rethrows errors from `body`
    /// - Returns: the result of `body`
    public func withCurrentDirectoryPath<Result>(_ path: String, body: () throws -> Result) throws -> Result {
        let oldPath = currentDirectoryPath
        guard changeCurrentDirectoryPath(path) else {
            throw ChangeDirectoryFailedError()
        }
        defer { _ = changeCurrentDirectoryPath(oldPath) }
        return try body()
    }
}

extension FileHandle {
    func closeIgnoringErrors() {
        #if os(Windows)
        try? close()
        #else
        close(fileDescriptor)
        #endif
    }
}

func printOSCall(_ name: String, _ args: Any?...) {
    print("OS Call: \(name)(\(args.map { $0.map { String(describing: $0) } ?? "null" }.joined(separator: ", ")))")
}
