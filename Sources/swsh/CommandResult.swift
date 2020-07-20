//
//  File.swift
//
//
//  Created by Andrew Cobb on 12/28/19.
//

import Foundation

/// Represents a running or finished command
public protocol CommandResult {
    /// The command that launched this result
    var command: Command { get }

    /// Returns true if the command is still running
    var isRunning: Bool { get }

    /// Block until command is finished, and return exit code
    func exitCode() -> Int32

    /// Block and throw an error if exitCode is non-zero
    func succeed() throws

    /// Sends a signal to a process,
    func kill(signal: Int32) throws
}

extension CommandResult {
    /// Wait for the command to finish, ignoring any exit code
    @discardableResult
    public func finish() -> Self {
        _ = exitCode()
        return self
    }

    /// A default implementation that can be used for succeed
    public func defaultSucceed(name: String = "\(Self.self)") throws {
        let err = exitCode()
        if err != 0 {
            throw ExitCodeFailure(name: name, exitCode: err)
        }
    }

    /// Sends a TERM signal to a process,
    public func kill() throws {
        try kill(signal: SIGTERM)
    }
}
