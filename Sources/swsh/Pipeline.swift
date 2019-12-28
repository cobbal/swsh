import Foundation

/// A `Pipeline` is 0 or more pipes connecting 1 or more subcommands together like bash's `a | b | ...`
public class Pipeline: Command {
    // Don't want to think about the base case, non-empty pipelines only
    private let first: Command
    private let rest: [Command]

    /// Create a pipeline from 1 or more sub-commands
    public init(_ first: Command, _ rest: Command...) {
        self.first = first
        self.rest = rest
    }

    private struct Result: CommandResult {
        let command: Command
        let results: [CommandResult]
        var isRunning: Bool { results.contains { $0.isRunning } }

        /// returns the rightmost non-zero exit code, to act similar to bash's pipefail option
        func exitCode() -> Int32 {
            results.reduce(into: 0) { code, result in
                _ = result.finish()
                if code == 0 {
                    code = result.exitCode()
                }
            }
        }

        func succeed() throws {
            try results.forEach { try $0.succeed() }
        }
    }

    public func coreAsync(fdMap baseFDMap: FDMap) -> CommandResult {
        let pipes = rest.map { _ in Pipe() }
        let inputs = [STDIN_FILENO] + pipes.map { $0.fileHandleForReading.fileDescriptor }
        let outputs = pipes.map { $0.fileHandleForWriting.fileDescriptor } + [STDOUT_FILENO]
        var results = [CommandResult]()
        for (command, (input, output)) in zip([first] + rest, zip(inputs, outputs)) {
            var fdMap = baseFDMap
            fdMap.append((input, STDIN_FILENO))
            fdMap.append((output, STDOUT_FILENO))
            results.append(command.coreAsync(fdMap: fdMap))
        }
        return Result(command: self, results: results)
    }
}

/// Convenience function to create a 2-command pipeline
public func | (_ left: Command, _ right: Command) -> Command { Pipeline(left, right) }

/// :nodoc:
public func | <R: Command>(_ left: Command, _ right: R) -> Command { Pipeline(left, right) }

/// :nodoc:
public func | <L: Command>(_ left: L, _ right: Command) -> Command { Pipeline(left, right) }

/// :nodoc:
public func | <L: Command, R: Command>(_ left: L, _ right: R) -> Command { Pipeline(left, right) }
