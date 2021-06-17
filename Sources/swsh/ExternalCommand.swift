import Foundation

/// Represents an external program invocation. It is the lowest-level command, that will spawn a subprocess when run.
public class ExternalCommand: Command {
    internal let command: String
    internal let arguments: [String]
    /// The environment variables the command will be launched with
    public let environment: [String: String]

    /// like "set -x", this will cause all external commands to print themselves when they run
    public static var verbose: Bool = false

    internal var spawner: ProcessSpawner

    /// Creates the command, but does **not** run it
    /// - Parameter command: The executable to run
    /// - Parameter arguments: The command line arguments to pass. No substitution is performed
    /// - Parameter addEnv: Additional environment variable that will be passed in addition to the swsh process's
    ///   environment
    public init(_ command: String, arguments: [String], addEnv: [String: String] = [:]) {
        self.command = command
        self.arguments = arguments
        self.environment = ProcessInfo.processInfo.environment.merging(addEnv) { $1 }
        #if canImport(Darwin)
        self.spawner = PosixSpawn()
        #elseif canImport(Glibc)
        self.spawner = LinuxSpawn()
        #endif
    }

    internal class Result: CommandResult {
        static let reaperQueue = DispatchQueue(label: "swsh.ExternalCommand.Result.reaper")

        let name: String
        var command: Command
        let pid: pid_t
        private var _exitCode: Int32?
        private var _exitSemaphore = DispatchSemaphore(value: 0)

        init(command: ExternalCommand, pid: pid_t) {
            self.command = command
            self.name = command.command
            self.pid = pid

            command.spawner.reapAsync(pid: pid, queue: Result.reaperQueue) { [weak self] in
                self?._exitCode = $0
                self?._exitSemaphore.signal()
            }

            try? kill(signal: SIGCONT)
        }

        var isRunning: Bool {
            Result.reaperQueue.sync { _exitCode == nil }
        }

        func kill(signal: Int32) throws {
            guard Foundation.kill(pid, signal) == 0 else {
                throw SyscallError(name: "kill", command: command, errno: errno)
            }
        }

        func succeed() throws { try defaultSucceed(name: name) }

        func exitCode() -> Int32 {
            _exitSemaphore.wait()
            _exitSemaphore.signal()
            return Result.reaperQueue.sync { _exitCode! }
        }
    }

    public func coreAsync(fdMap: FDMap) -> CommandResult {
        if ExternalCommand.verbose {
            var stream = FileHandleTextStream(.standardError)
            print("\(command) \(arguments.joined(separator: " "))", to: &stream)
        }

        switch spawner.spawn(
          command: command,
          arguments: arguments,
          env: environment,
          fdMap: fdMap,
          pathResolve: true
        ) {
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
    ExternalCommand(command, arguments: arguments, addEnv: addEnv)
}

/// Convenience function for creating an extternal command. Does **not** run the command.
/// - Parameter command: The executable to run
/// - Parameter arguments: The command line arguments to pass. No substitution is performed
public func cmd(_ command: String, _ arguments: String..., addEnv: [String: String] = [:]) -> Command {
    ExternalCommand(command, arguments: arguments, addEnv: addEnv)
}
