//
//  Command.swift
//
//
//  Created by Andrew Cobb on 11/6/19.
//

import Foundation

public protocol CommandResult {
    /// The command that launched this result
    var command: Command { get }
    var isRunning: Bool { get }

    /// block until command is finished, and return exit code
    func exitCode() -> Int32
}

public extension CommandResult {
    /// throws CommandFailure if exitCode is non-zero
    func succeed() throws {
        if exitCode() != 0 {
            throw CommandFailure(result: self)
        }
    }

    func finish() -> Self {
        _ = exitCode()
        return self
    }
}

public protocol Command: class {
    typealias FDMap = [(src: Int32, dst: Int32)]
    // These should be a FileHandle or Pipe
    func coreAsync(fdMap: FDMap) -> CommandResult
}

public extension Command {
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

    /// Return stream open on process's stdout
    func asyncStream(joinErr: Bool = false) throws -> FileHandle {
        let pipe = Pipe()
        let pipeFD = pipe.fileHandleForWriting.fileDescriptor
        _ = coreAsync(fdMap: [(STDIN_FILENO, STDIN_FILENO),
                              (pipeFD, STDOUT_FILENO),
                              (joinErr ? pipeFD : STDERR_FILENO, STDERR_FILENO)])
        close(pipeFD)
        return pipe.fileHandleForReading
    }

    /// Run and return nothing if successful
    func run() throws {
        try async().succeed()
    }

    /// Returns true if the command exited zero
    func runBool() -> Bool {
        return async().exitCode() == 0
    }

    /// Process > temp file; return file path
    func runFile() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString, isDirectory: false)
        let handle = try FileHandle(forWritingTo: url)
        try async(stdout: handle.fileDescriptor).succeed()
        return url
    }

    /// Collect stdout and then return, does not trim (unlike $(...))
    func runData(joinErr: Bool = false) throws -> Data {
        let pipe = Pipe()
        let writeFD = pipe.fileHandleForWriting.fileDescriptor
        let result = async(stdout: writeFD, stderr: joinErr ? writeFD : STDERR_FILENO)
        close(writeFD)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        try result.succeed()
        return data
    }

    /// Collect stdout into a string and return, trimming trailing newlines (like $(...))
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

    /// Collect newline-delimited list of strings
    func runLines() throws -> [String] {
        try runString().split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    /// Collect JSON
    func runJson(options: JSONSerialization.ReadingOptions = .allowFragments) throws -> Any {
        try JSONSerialization.jsonObject(with: runData(), options: options)
    }
}

public func cmd(_ command: String, arguments: [String]) -> BasicCommand {
    return BasicCommand(command, arguments: arguments)
}

public func cmd(_ command: String, _ arguments: String...) -> BasicCommand {
    return BasicCommand(command, arguments: arguments)
}

//// StaticString to help preven accidental quoting problems
//public func cmdf(_ format: StaticString, _ formatArgs: Any...) -> BasicCommand {
//    let formatStr = format.withUTF8Buffer {
//        String(decoding: $0, as: UTF8.self)
//    }
//
//    let components = formatStr.components(separatedBy: .whitespacesAndNewlines)
//
//}
