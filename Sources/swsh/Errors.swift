//
//  File.swift
//  
//
//  Created by Andrew Cobb on 11/8/19.
//

import Foundation

public struct InvalidString: Error {
    let data: Data
    let encoding: String.Encoding
}

public struct CommandFailure: Error {
    let result: CommandResult

    var localizedDescription: String {
        "command \(result.command) failed with exit code \(result.exitCode())"
    }
}

public struct ProcessLaunchError: Error, CommandResult {
    public let command: Command
    public let error: Error
    public var isRunning: Bool { false }
    public func exitCode() -> Int32 { -1 }
}
