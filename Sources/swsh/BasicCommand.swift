//
//  BasicCommand.swift
//  
//
//  Created by Andrew Cobb on 11/8/19.
//

import Foundation

public class BasicCommand: Command {
    internal let command: String
    internal let arguments: [String]
    public let environment: [String: String]

    /// like "set -x"
    public static var verbose: Bool = false

    public init(_ command: String, arguments: [String], addEnv: [String: String] = [:]) {
        self.command = command
        self.arguments = arguments
        self.environment = ProcessInfo.processInfo.environment.merging(addEnv) { $1 }
    }
    
    public struct ExitCodeFailure: Error, CustomStringConvertible {
        public let name: String
        let result: Result
        
        public var description: String {
            "command \"\(name)\" failed with exit code \(result.exitCode())"
        }
    }

    public class ProcessLaunchFailure: Error, CommandResult, CustomStringConvertible {
        public var command: Command
        public let name: String
        public let error: Int32
        public var isRunning: Bool { false }
        public func exitCode() -> Int32 { error }
        
        init(command: BasicCommand, error: Int32) {
            self.command = command
            self.name = command.command
            self.error = error
        }
        
        public var description: String {
            "failed to launch \"\(name)\" with error code \(error): \(String(cString: strerror(error)))"
        }

        public func succeed() throws {
            throw self
        }
    }

    internal class Result: CommandResult {
        static let reaperQueue = DispatchQueue(label: "swsh.BasicCommand.Result.reaper")

        let name: String
        var command: Command
        let pid: pid_t
        private var _exitCode: Int32? = nil
        private var _exitSemaphore = DispatchSemaphore(value: 0)
        let processSource: DispatchSourceProcess

        init(command: BasicCommand, pid: pid_t) {
            self.command = command
            self.name = command.command
            self.pid = pid

            processSource = DispatchSource.makeProcessSource( identifier: pid, eventMask: .exit, queue: Self.reaperQueue)
            processSource.setEventHandler { [weak self, processSource] in
                var status: Int32 = 0
                waitpid(pid, &status, 0)
                self?._exitCode = status
                self?._exitSemaphore.signal()
                processSource.cancel()
            }
            processSource.activate()
            kill(pid, SIGCONT)
        }

        var isRunning: Bool {
            Self.reaperQueue.sync { _exitCode == nil }
        }
        
        func succeed() throws {
            if exitCode() != 0 {
                throw ExitCodeFailure(name: name, result: self)
            }
        }

        func exitCode() -> Int32 {
            _exitSemaphore.wait()
            _exitSemaphore.signal()
            return Self.reaperQueue.sync { _exitCode! }
        }
    }

    public func coreAsync(fdMap: FDMap) -> CommandResult {
        if BasicCommand.verbose {
            var stream = FileHandleTextStream(.standardError)
            print("\(command) \(arguments.joined(separator: " "))", to: &stream)
        }

        switch spawn(command: command, arguments: arguments, env: environment, fdMap: fdMap) {
        case .success(let pid):
            return Result(command: self, pid: pid)
        case .error(let err):
            return ProcessLaunchFailure(command: self, error: err)
        }
    }
}
