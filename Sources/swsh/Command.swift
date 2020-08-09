import Foundation

/// Represents a description of a command that can be executed any number of times, but usually just once.
public protocol Command: class {
    /// The minimum requirement of a Command is that it can launch itself asynchronously
    /// - Parameter fdMap: A map from child FDs to parent FDs
    /// - Returns: a result capable of monitoring the asynchronous command
    func coreAsync(fdMap: FDMap) -> CommandResult
}

extension Command {
    // MARK: - Running

    internal var standardFdMap: FDMap { return [
        .stdin: .stdin,
        .stdout: .stdout,
        .stderr: .stderr,
    ] }

    /// Run the command asynchronously, inheriting or overwriting the standard file descriptors
    /// - Parameter fdMap: A map from child FDs to parent FDs, will be composed with standard map
    /// - Returns: a result capable of monitoring the asynchronous command
    public func async(fdMap: FDMap = [:]) -> CommandResult {
        return coreAsync(fdMap: fdMap.compose(standardFdMap))
    }

     /// Run the command asynchronously, inheriting or overwriting the standard file descriptors
    public func async(
        stdin: FileDescriptor = .stdin,
        stdout: FileDescriptor = .stdout,
        stderr: FileDescriptor = .stderr
    ) -> CommandResult {
        return coreAsync(fdMap: [.stdin: stdin, .stdout: stdout, .stderr: stderr])
    }

    /// Run the command asynchronously, and return a stream open on process's stdout
    public func asyncStream() -> FileHandle {
        let pipe = Pipe()
        let write = pipe.fileHandleForWriting
        _ = async(fdMap: [ .stdout: write.fd ])
        close(write.fileDescriptor)
        return pipe.fileHandleForReading
    }

    /// Run the command synchronously, and return nothing if successful
    /// - Throws: if command fails
    public func run() throws {
        try async().succeed()
    }

    /// Run the command synchronously, and return true if the command exited zero
    public func runBool() -> Bool {
        return async().exitCode() == 0
    }

    /// Run the command synchronously, directing the output to a temporary file
    /// - Returns: URL of temporary file with output of command
    /// - Throws: if command fails
    public func runFile() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
          .appendingPathComponent(UUID().uuidString, isDirectory: false)
        try self.output(creatingFile: url.path).run()
        return url
    }

    /// Run the command synchronously, and collect stdout.
    /// does not trim newlines (unlike $(...))
    /// - Throws: if command fails
    /// - Returns: output as Data
    public func runData() throws -> Data {
        let pipe = Pipe()
        let write = pipe.fileHandleForWriting
        let result = async(fdMap: [ .stdout: write.fd ])
        close(write.fileDescriptor)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        try result.succeed()
        return data
    }

    /// Run the command synchronously, and collect stdout into a string.
    /// Trims trailing newlines (like $(...))
    /// - Parameter encoding: the encoding of the output data
    /// - Throws: if command fails
    /// - Throws: `InvalidString` if the output isn't valid
    /// - Returns: output as unicode string
    public func runString(encoding: String.Encoding = .utf8) throws -> String {
        let data = try runData()
        guard let string = String(data: data, encoding: encoding) else {
            throw InvalidString(data: data, encoding: encoding)
        }
        guard let trimStop = string.lastIndex(where: { $0 != "\n" }) else {
            return ""
        }
        return String(string[...trimStop])
    }

    /// Run the command synchronously, and collect output line-by-line as a list of strings
    /// - Throws: if command fails
    public func runLines(encoding: String.Encoding = .utf8) throws -> [String] {
        let lines = try runString(encoding: encoding).split(separator: "\n", omittingEmptySubsequences: false)
        return lines.map(String.init)
    }

    /// Run the command synchronously, and collect output as a parsed JSON object
    /// - Throws: if command fails
    /// - Throws: if the output isn't JSON
    public func runJSON(options: JSONSerialization.ReadingOptions = .allowFragments) throws -> Any {
        return try JSONSerialization.jsonObject(with: runData(), options: options)
    }

    /// Run the command synchronously, and collect output as a parsed JSON object
    /// - Throws: if command fails
    /// - Throws: if parsing fails
    public func runJSON<D: Decodable>(_ type: D.Type, decoder: JSONDecoder? = nil) throws -> D {
        let decoder = decoder ?? JSONDecoder()
        return try decoder.decode(type, from: runData())
    }
}
