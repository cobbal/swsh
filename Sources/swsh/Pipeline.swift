//
//  File.swift
//  
//
//  Created by Andrew Cobb on 11/8/19.
//

import Foundation

public class Pipeline: Command {
    // Don't want to think about the base case, non-empty pipelines only
    private let first: Command
    private let rest: [Command]

    public init(_ first: Command, _ rest: Command...) {
        self.first = first
        self.rest = rest
    }

    private struct Result: CommandResult {
        let command: Command
        let results: [CommandResult]

        var isRunning: Bool {
            return results.contains { $0.isRunning }
        }

        func exitCode() -> Int32 {
            // get the rightmost non-zero exit code, to act similar to bash's pipefail option
            results.reduce(into: 0) { code, result in
                _ = result.finish()
                if code == 0 {
                    code = result.exitCode()
                }
            }
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
