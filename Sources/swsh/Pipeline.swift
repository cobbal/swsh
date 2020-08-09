import Foundation

/// A `Pipeline` is 0 or more pipes connecting 1 or more subcommands together like bash's `a | b | ...`
public class Pipeline: Command {
    // Don't want to think about the base case, non-empty pipelines only
    internal let first: Command
    internal let rest: [Command]

    /// Create a pipeline from 1 or more sub-commands
    public init(_ first: Command, _ rest: Command...) {
        self.first = first
        self.rest = rest
    }

    internal struct Result: CommandResult {
        let command: Command
        let results: [CommandResult]
        var isRunning: Bool { return results.contains { $0.isRunning } }

        /// returns the rightmost non-zero exit code, to act similar to bash's pipefail option
        func exitCode() -> Int32 {
            return results.reduce(into: 0 as Int32) { code, result in
                _ = result.finish()
                if code == 0 {
                    code = result.exitCode()
                }
            }
        }

        func succeed() throws {
            try results.forEach { try $0.succeed() }
        }

        func kill(signal: Int32) throws {
            var signalError: Error?
            for result in results {
                do {
                    try result.kill(signal: signal)
                } catch let error {
                    signalError = signalError ?? error
                }
            }
            try signalError.map { throw $0 }
        }
    }

    public func coreAsync(fdMap baseFDMap: FDMap) -> CommandResult {
        let pipes = rest.map { _ in Pipe() }
        let inputs = [.stdin] + pipes.map { $0.fileHandleForReading.fd }
        let outputs = pipes.map { $0.fileHandleForWriting.fd } + [.stdout]
        var results = [CommandResult]()
        for (command, (input, output)) in zip([first] + rest, zip(inputs, outputs)) {
            var fdMap = baseFDMap
            fdMap = fdMap.compose([.stdin: input, .stdout: output])
            results.append(command.coreAsync(fdMap: fdMap))
        }
        return Result(command: self, results: results)
    }
}

/// Convenience function to create a 2-command pipeline
public func | (_ left: Command, _ right: Command) -> Command { return Pipeline(left, right) }
