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

    // like "set -x"
    public static var verbose: Bool = false

    public init(_ command: String, arguments: [String], addEnv: [String: String] = [:]) {
        self.command = command
        self.arguments = arguments
        self.environment = ProcessInfo.processInfo.environment.merging(addEnv) { $1 }
    }

    internal class Result: CommandResult {
        static let reaperQueue = DispatchQueue(label: "swsh.BasicCommand.Result.reaper")

        var command: Command
        let pid: pid_t
        private var _exitCode: Int32? = nil
        private var _exitSemaphore = DispatchSemaphore(value: 0)
        let processSource: DispatchSourceProcess

        init(command: Command, pid: pid_t) {
            self.command = command
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

        let pid: pid_t
        do {
            pid = try spawn(command: command, arguments: arguments, env: environment, fdMap: fdMap)
        } catch let e {
            return ProcessLaunchError(command: self, error: e)
        }

        return Result(command: self, pid: pid)
    }

    internal func spawn(command: String,
                        arguments: [String],
                        env: [String: String],
                        fdMap: Command.FDMap,
                        pathResolve: Bool = true) throws -> pid_t
    {
        var fileActions: posix_spawn_file_actions_t? = nil
        posix_spawn_file_actions_init(&fileActions)
        defer { posix_spawn_file_actions_destroy(&fileActions) }

        var attrs: posix_spawnattr_t? = nil
        posix_spawnattr_init(&attrs)
        defer { posix_spawnattr_destroy(&attrs) }

        // Don't implicitly dunplicate descriptors
        // Start suspended to avoid race condition with the handler setup
        posix_spawnattr_setflags(&attrs, Int16(POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_START_SUSPENDED))
        for (srcFd, dstFd) in fdMap {
            posix_spawn_file_actions_adddup2(&fileActions, srcFd, dstFd)
        }

        let cCommand = command.withCString(strdup)
        var cArgs = [cCommand]
        cArgs.append(contentsOf:arguments.map { $0.withCString(strdup) })
        cArgs.append(nil)

        var cEnv = env.map { "\($0)=\($1)".withCString(strdup) }
        cEnv.append(nil)

        defer {
            cArgs.forEach { free($0) }
            cEnv.forEach { free($0) }
        }

        var pid = pid_t()
        let spawn_fn = pathResolve ? posix_spawnp : posix_spawn
        let res = spawn_fn(&pid, cCommand, &fileActions, &attrs, cArgs, cEnv)

        if res != 0 {
            throw SpawnError(errnum: res)
        }

        return pid
    }
}

