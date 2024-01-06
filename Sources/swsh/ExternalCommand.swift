import Foundation
#if os(Windows)
import WinSDK
#endif

/// Represents an external program invocation. It is the lowest-level command, that will spawn a subprocess when run.
public class ExternalCommand: Command, CustomStringConvertible {
    internal let command: String
    internal let arguments: [String]
    /// The environment variables the command will be launched with
    public let environment: [String: String]

    public let description: String

    /// Like "set -x", this will cause all external commands to print themselves when they run
    public static var verbose: Bool = false

    /// Adds to the path variable when modifying the environment directly is impossible
    public static var supplementaryPath: String = ""

    internal var spawner: ProcessSpawner

    internal static let safeCharacters = CharacterSet(
        charactersIn: "/%+-.0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz"
    )

    internal static func escape(_ str: String) -> String {
        if str.isEmpty {
            return "''"
        } else if str.unicodeScalars.allSatisfy(safeCharacters.contains) {
            return str
        } else {
            return "'\(str.replacingOccurrences(of: "'", with: #"'\''"#))'"
        }
    }

    /// Creates the command, but does **not** run it
    /// - Parameter command: The executable to run
    /// - Parameter arguments: The command line arguments to pass. No substitution is performed
    /// - Parameter addEnv: Additional environment variable that will be passed in addition to the swsh process's
    ///   environment
    public init(_ command: String, arguments: [String], addEnv: [String: String] = [:]) {
        self.command = command
        self.arguments = arguments
        self.environment = ProcessInfo.processInfo.environment.merging(addEnv) { $1 }

        var descriptionParts: [String] = []
        for env in addEnv.sorted(by: { $0.key < $1.key }) {
            descriptionParts.append("\(Self.escape(env.key))=\(Self.escape(env.value))")
        }
        descriptionParts.append(Self.escape(command))
        descriptionParts.append(contentsOf: arguments.map(Self.escape))
        self.description = descriptionParts.joined(separator: " ")

        #if canImport(Darwin)
        self.spawner = PosixSpawn()
        #elseif canImport(Glibc)
        self.spawner = LinuxSpawn()
        #elseif canImport(ucrt)
        self.spawner = WindowsSpawn()
        #endif
    }

    internal class Result: CommandResult, AsyncCommandResult {
        static let reaperQueue = DispatchQueue(label: "swsh.ExternalCommand.Result.reaper")

        let name: String
        var command: Command
        let process: ProcessInformation
        
        private var _exitCode: Int32?
        private var _exitSemaphore = DispatchSemaphore(value: 0)
        private var _exitContinuations: [() -> Void] = []

        init(command: ExternalCommand, process: ProcessInformation) {
            self.command = command
            self.name = command.command
            self.process = process
            
            command.spawner.reapAsync(process: process, queue: Result.reaperQueue) { [weak self] exitCode in
                self?._exitCode = exitCode
                self?._exitSemaphore.signal()
                self?._exitContinuations.forEach { $0() }
                self?._exitContinuations = []
            }

            try? command.spawner.resume(process: process)
        }

        var isRunning: Bool {
            Result.reaperQueue.sync { _exitCode == nil }
        }
        
        static let NtSuspendProcess: (ProcessInformation) -> Int32 = {
            // TODO: Tie into (undocumented) NtSuspendProcess() syscall
            return { _ in 0 }
        }()

        static let NtResumeProcess: (ProcessInformation) -> Int32 = {
            // TODO: Tie into (undocumented) NtResumeProcess() syscall
            return { _ in 0 }
        }()

        func kill(signal: Int32) throws {
            #if os(Windows)
            // TODO: figure out how to do this in-executable?
            if signal == SIGTERM || signal == SIGKILL {
                try cmd("taskkill.exe", "/F", "/pid", "\(process.id)").run()
            } else if signal == SIGSTOP {
                // Method borrowed from https://github.com/giampaolo/psutil/blob/a7e70bb66d5823f2cdcdf0f950bdbf26875058b4/psutil/arch/windows/proc.c#L539
                // See also https://ntopcode.wordpress.com/2018/01/16/anatomy-of-the-thread-suspension-mechanism-in-windows-windows-internals/
                _ = Self.NtSuspendProcess(process)
            } else if signal == SIGCONT {
                _ = Self.NtResumeProcess(process)
            } else {
                throw PlatformError.killUnsupportedOnWindows
            }
            #else
            guard Foundation.kill(process.id, signal) == 0 else {
                throw SyscallError(name: "kill", command: command, errno: errno)
            }
            #endif
        }

        func succeed() throws { try defaultSucceed(name: name) }

        func exitCode() -> Int32 {
            _exitSemaphore.wait()
            _exitSemaphore.signal()
            return Result.reaperQueue.sync { _exitCode! }
        }

        #if compiler(>=5.5) && canImport(_Concurrency)
        @available(macOS 10.15, *)
        func asyncFinish() async {
            await withCheckedContinuation { (kont: CheckedContinuation<Void, Never>) in
                Result.reaperQueue.sync {
                    if _exitCode != nil {
                        kont.resume()
                    } else {
                        _exitContinuations.append { kont.resume() }
                    }
                }
            }
        }
        #endif
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
        case .success(let process):
            return Result(command: self, process: process)
        case .error(let err):
            return SyscallError(name: "launching \"\(command)\"", command: self, errno: err)
        }
    }
}

/// Convenience function for creating an external command. Does **not** run the command.
/// - Parameter command: The executable to run
/// - Parameter arguments: The command line arguments to pass. No substitution is performed
public func cmd(_ command: String, arguments: [String], addEnv: [String: String] = [:]) -> Command {
    ExternalCommand(command, arguments: arguments, addEnv: addEnv)
}

/// Convenience function for creating an external command. Does **not** run the command.
/// - Parameter command: The executable to run
/// - Parameter arguments: The command line arguments to pass. No substitution is performed
public func cmd(_ command: String, _ arguments: String..., addEnv: [String: String] = [:]) -> Command {
    ExternalCommand(command, arguments: arguments, addEnv: addEnv)
}
