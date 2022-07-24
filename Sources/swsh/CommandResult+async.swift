import Foundation

#if compiler(>=5.5) && canImport(_Concurrency)

@available(macOS 10.15, *)
internal protocol AsyncCommandResult: CommandResult {
    func asyncFinish() async
}

extension CommandResult {
    func withSyncContext<R>(f: () throws -> R) rethrows -> R { try f() }

    @available(macOS 10.15, *)
    internal func asyncFinishInternal() async {
        if let asyncSelf = self as? AsyncCommandResult {
            await asyncSelf.asyncFinish()
        } else {
            _ = await Task { exitCode() }.result
        }
    }

    /// return exit code asynchronously
    @available(macOS 10.15, *)
    public func exitCode() async -> Int32 {
        await asyncFinishInternal()
        return withSyncContext { exitCode() }
    }

    /// throw an error if exitCode is non-zero asynchronously
    @available(macOS 10.15, *)
    public func succeed() async throws {
        await asyncFinishInternal()
        return try withSyncContext { try succeed() }
    }

    /// Wait for the command to finish, ignoring any exit code
    @discardableResult
    @available(macOS 10.15, *)
    public func finish() async -> Self {
        await asyncFinishInternal()
        return self
    }
}

#else

protocol AsyncCommandResult: CommandResult {}

#endif
