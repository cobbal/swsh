import Foundation

/// Represents an external program invocation. It is the lowest-level command, that will spawn a subprocess when run.
public class ExternalCommand: Command {
    internal let command: String
    internal let arguments: [String]
    /// The environment variables the command will be launched with
    public let environment: [String: String]

    /// like "set -x", this will cause all external commands to print themselves when they run
    public static var verbose: Bool = false

    /// Creates the command, but does **not** run it
    /// - Parameter command: The executable to run
    /// - Parameter arguments: The command line arguments to pass. No substitution is performed
    /// - Parameter addEnv: Additional environment variable that will be passed in addition to the swsh process's
    ///   environment
    public init(_ command: String, arguments: [String], addEnv: [String: String] = [:]) {
        self.command = command
        self.arguments = arguments
        self.environment = ProcessInfo.processInfo.environment.merging(addEnv) { $1 }
    }

    internal class Result: CommandResult {
        static let reaperQueue = DispatchQueue(label: "swsh.ExternalCommand.Result.reaper")

        let name: String
        var command: Command
        let pid: pid_t
        private var _exitCode: Int32?
        private var _exitSemaphore = DispatchSemaphore(value: 0)
        let processSource: DispatchSourceProcess

        // C macros are unfortunately not bridged to swift, borrowed from Foundation/Process
        private static func WIFEXITED(_ status: Int32) -> Bool { _WSTATUS(status) == 0 }
        private static func _WSTATUS(_ status: Int32) -> Int32 { status & 0x7f }
        private static func WEXITSTATUS(_ status: Int32) -> Int32 { (status >> 8) & 0xff }

        init(command: ExternalCommand, pid: pid_t) {
            self.command = command
            self.name = command.command
            self.pid = pid

            processSource = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: Self.reaperQueue)
            processSource.setEventHandler { [weak self, processSource] in
                var status: Int32 = 0
                waitpid(pid, &status, 0)
                if Self.WIFEXITED(status) {
                    self?._exitCode = Self.WEXITSTATUS(status)
                    self?._exitSemaphore.signal()
                    processSource.cancel()
                }
            }
            processSource.activate()
            kill(pid, SIGCONT)
        }

        var isRunning: Bool {
            Self.reaperQueue.sync { _exitCode == nil }
        }

        func succeed() throws { try defaultSucceed(name: name) }

        func exitCode() -> Int32 {
            _exitSemaphore.wait()
            _exitSemaphore.signal()
            return Self.reaperQueue.sync { _exitCode! }
        }
    }

    public func coreAsync(fdMap: FDMap) -> CommandResult {
        if ExternalCommand.verbose {
            var stream = FileHandleTextStream(.standardError)
            print("\(command) \(arguments.joined(separator: " "))", to: &stream)
        }

        switch PosixSpawn.spawn(command: command, arguments: arguments, env: environment, fdMap: fdMap) {
        case .success(let pid):
            return Result(command: self, pid: pid)
        case .error(let err):
            return SyscallError(name: "launching \"\(command)\"", command: self, errno: err)
        }
    }
}

/// Convenience function for creating an extternal command. Does **not** run the command.
/// - Parameter command: The executable to run
/// - Parameter arguments: The command line arguments to pass. No substitution is performed
public func cmd(_ command: String, arguments: [String], addEnv: [String: String] = [:]) -> Command {
    return ExternalCommand(command, arguments: arguments, addEnv: addEnv)
}

/// Convenience function for creating an extternal command. Does **not** run the command.
/// - Parameter command: The executable to run
/// - Parameter arguments: The command line arguments to pass. No substitution is performed
public func cmd(_ command: String, _ arguments: String..., addEnv: [String: String] = [:]) -> Command {
    return ExternalCommand(command, arguments: arguments, addEnv: addEnv)
}
