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

    internal struct Result: CommandResult, AsyncCommandResult {
        let command: Command
        let results: [CommandResult]
        var isRunning: Bool { results.contains { $0.isRunning } }

        /// returns the rightmost non-zero exit code, to act similar to bash's pipefail option
        func exitCode() -> Int32 {
            results.reduce(into: 0 as Int32) { code, result in
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
            var signalErrors: [Error?] = []
            for result in results {
                do {
                    try result.kill(signal: signal)
                    signalErrors.append(nil)
                } catch let error {
                    signalErrors.append(error)
                }
            }
            if !signalErrors.contains(where: { $0 == nil }) {
                try signalErrors.first?.map { throw $0 }
            }
        }


        #if compiler(>=5.5) && canImport(_Concurrency)
        @available(macOS 10.15, *)
        func asyncFinish() async {
            for result in results {
                await result.asyncFinishInternal()
            }
        }
        #endif
    }

    public func coreAsync(fdMap baseFDMap: FDMap) -> CommandResult {
        let pipes = rest.map { _ in FDPipe() }
        let inputs = [FileDescriptor.stdin] + pipes.map(\.fileHandleForReading.fileDescriptor)
        let outputs = pipes.map(\.fileHandleForWriting.fileDescriptor) + [FileDescriptor.stdout]
        var results = [CommandResult]()
        for (command, (input, output)) in zip([first] + rest, zip(inputs, outputs)) {
            var fdMap = baseFDMap
            fdMap = fdMap.compose([.stdin: input, .stdout: output])
            results.append(command.coreAsync(fdMap: fdMap))
        }
        return Result(command: self, results: results)
    }
}

extension Pipeline: CustomStringConvertible {
    public var description: String {
        ([first] + rest).map(String.init(describing:)).joined(separator: " | ")
    }
}

/// Convenience function to create a 2-command pipeline
public func | (_ left: Command, _ right: Command) -> Command { Pipeline(left, right) }
