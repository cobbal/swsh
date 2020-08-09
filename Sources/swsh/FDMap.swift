import Foundation

/// A mapping from the child process's file descriptors to open ones in the
/// parent. For instance, mapping both a child's output and error to go to
/// stdout would be represented as [1: 1, 2: 1]
public typealias FDMap = [FileDescriptor: FileDescriptor]

extension FDMap {
    /// joins 2 maps together. If a FDMap is a child -> parent mapping
    /// - Parameter self: intermediate -> parent
    /// - Parameter other: child -> intermediate
    /// - Returns: child -> parent
    public func compose(_ other: FDMap) -> FDMap {
        var result: FDMap = [:]
        for (dst, src) in other {
            result[dst] = self[src] ?? src
        }
        for (dst, src) in self {
            result[dst] ??= src
        }
        return result
    }
}

extension FDMap {
    internal func createFdOperations() -> [FDOperation] {
        var generator = FDOperation.Remapper(self)
        return generator.generate()
    }
}
