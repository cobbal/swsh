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
}

public extension CommandResult {
    /// Wait for the command to finish, ignoring any exit code
    func finish() -> Self {
        _ = exitCode()
        return self
    }
}

/// Represents a description of a command that can be executed any number of times, but usually just once.
public protocol Command: class {
    typealias FDMap = [(src: Int32, dst: Int32)]
    /// The minimum requirement of a Command is that it can launch itself asynchronously
    /// - Parameter fdMap: A list of file descriptors to remap. Order matters, same as in bourne-like shells.
    /// - Returns: a result capable of monitoring the asynchronous command
    func coreAsync(fdMap: FDMap) -> CommandResult
}

public extension Command {
    /// Convenience function to create a 2-command pipeline
    static func | (_ left: Self, _ right: Command) -> Command {
        Pipeline(left, right)
    }

    internal func async(stdin: Int32 = STDIN_FILENO,
                        stdout: Int32 = STDOUT_FILENO,
                        stderr: Int32 = STDERR_FILENO) -> CommandResult
    {
        return coreAsync(fdMap: [(stdin, STDIN_FILENO),
                                 (stdout, STDOUT_FILENO),
                                 (stderr, STDERR_FILENO)])
    }

    /// Run the command asynchronously, and return a stream open on process's stdout
    func asyncStream(joinErr: Bool = false) -> FileHandle {
        let pipe = Pipe()
        let pipeFD = pipe.fileHandleForWriting.fileDescriptor
        _ = coreAsync(fdMap: [(STDIN_FILENO, STDIN_FILENO),
                              (pipeFD, STDOUT_FILENO),
                              (joinErr ? pipeFD : STDERR_FILENO, STDERR_FILENO)])
        close(pipeFD)
        return pipe.fileHandleForReading
    }

    /// Run the command synchronously, and return nothing if successful
    /// - Throws: if command fails
    func run() throws {
        try async().succeed()
    }

    /// Run the command synchronously, and return true if the command exited zero
    func runBool() -> Bool {
        async().exitCode() == 0
    }

    /// Run the command synchronously, directing the output to a temporary file
    /// - Returns: URL of temporary file with output of command
    /// - Throws: if command fails
    func runFile() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString, isDirectory: false)
        let handle = try FileHandle(forWritingTo: url)
        try async(stdout: handle.fileDescriptor).succeed()
        return url
    }

    /// Run the command synchronously, and collect stdout.
    /// does not trim newlines (unlike $(...))
    /// - Parameter joinErr: if true, stderr will be collected as well
    /// - Throws: if command fails
    /// - Returns: output as Data
    func runData(joinErr: Bool = false) throws -> Data {
        let pipe = Pipe()
        let writeFD = pipe.fileHandleForWriting.fileDescriptor
        let result = async(stdout: writeFD, stderr: joinErr ? writeFD : STDERR_FILENO)
        close(writeFD)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        try result.succeed()
        return data
    }

    /// Run the command synchronously, and collect stdout into a string.
    /// Trims trailing newlines (like $(...))
    /// - Parameter encoding: the encoding of the output data
    /// - Parameter joinErr: if true, stderr will be collected as well
    /// - Throws: if command fails
    /// - Throws: `InvalidString` if the output isn't valid
    /// - Returns: output as unicode string
    func runString(encoding: String.Encoding = .utf8, joinErr: Bool = false) throws -> String {
        let data = try runData(joinErr: joinErr)
        guard let string = String(data: data, encoding: encoding) else {
            throw InvalidString(data: data, encoding: encoding)
        }
        guard let trimStop = string.lastIndex(where: { $0 != "\n" }) else {
            return ""
        }
        return String(string[...trimStop])
    }

    /// Run the command synchronously, and collect output as a newline-delimited list of strings
    /// - Throws: if command fails
    func runLines() throws -> [String] {
        try runString().split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    /// Run the command synchronously, and collect output as a parsed JSON object
    /// - Throws: if command fails
    /// - Throws: if the output isn't JSON
    func runJson(options: JSONSerialization.ReadingOptions = .allowFragments) throws -> Any {
        try JSONSerialization.jsonObject(with: runData(), options: options)
    }
}
