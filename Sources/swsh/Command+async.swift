import Foundation

#if compiler(>=5.5) && canImport(_Concurrency)

extension Command {
    // MARK: - Running

    /// Run the command asynchronously, and return nothing if successful
    /// - Throws: if command fails
    @available(macOS 10.15, *)
    public func run() async throws {
        try await async().succeed()
    }

    /// Run the command asynchronously, and return true if the command exited zero
    @available(macOS 10.15, *)
    public func runBool() async -> Bool {
        await async().exitCode() == 0
    }

    /// Run the command synchronously, directing the output to a temporary file
    /// - Returns: URL of temporary file with output of command
    /// - Throws: if command fails
    @available(macOS 10.15, *)
    public func runFile() async throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
          .appendingPathComponent(UUID().uuidString, isDirectory: false)
        try await self.output(creatingFile: url.path).run()
        return url
    }

    /// Run the command synchronously, and collect stdout.
    /// does not trim newlines (unlike $(...))
    /// - Throws: if command fails
    /// - Returns: output as Data
    @available(macOS 10.15, *)
    public func runData() async throws -> Data {
        let pipe = Pipe()
        let write = pipe.fileHandleForWriting
        let result = async(fdMap: [ .stdout: write.fd ])
        close(write.fileDescriptor)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        try await result.succeed()
        return data
    }

    /// Run the command asynchronously, and collect stdout into a string.
    /// Trims trailing newlines (like $(...))
    /// - Parameter encoding: the encoding of the output data
    /// - Throws: if command fails
    /// - Throws: `InvalidString` if the output isn't valid
    /// - Returns: output as unicode string
    @available(macOS 10.15, *)
    public func runString(encoding: String.Encoding = .utf8) async throws -> String {
        let data = try await runData()
        guard let string = String(data: data, encoding: encoding) else {
            throw InvalidString(data: data, encoding: encoding)
        }
        guard let trimStop = string.lastIndex(where: { $0 != "\n" }) else {
            return ""
        }
        return String(string[...trimStop])
    }

    /// Run the command asynchronously, and collect output line-by-line as a list of strings
    /// - Throws: if command fails
    @available(macOS 10.15, *)
    public func runLines(encoding: String.Encoding = .utf8) async throws -> [String] {
        let lines = try await runString(encoding: encoding).split(separator: "\n", omittingEmptySubsequences: false)
        return lines.map(String.init)
    }

    /// Run the command asynchronously, and collect output as a parsed JSON object
    /// - Throws: if command fails
    /// - Throws: if the output isn't JSON
    @available(macOS 10.15, *)
    public func runJSON(options: JSONSerialization.ReadingOptions = .allowFragments) async throws -> Any {
        try JSONSerialization.jsonObject(with: await runData(), options: options)
    }

    /// Run the command asynchronously, and collect output as a parsed JSON object
    /// - Throws: if command fails
    /// - Throws: if parsing fails
    @available(macOS 10.15, *)
    public func runJSON<D: Decodable>(_ type: D.Type, decoder: JSONDecoder? = nil) async throws -> D {
        let decoder = decoder ?? JSONDecoder()
        return try decoder.decode(type, from: await runData())
    }
}

#endif
