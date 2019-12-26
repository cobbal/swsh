//
//  FDWrapperCommand.swift
//
//
//  Created by Andrew Cobb on 12/26/19.
//

import Foundation

/// Wraps an inner command with file handle manipulation
internal class FDWrapperCommand: Command {
    enum FileOpenResult {
        case success(fdMap: FDMap, ref: Any?)
        case failure(CommandResult)
    }

    typealias FileOpener = (FDWrapperCommand) -> FileOpenResult

    internal let inner: Command
    internal let fdMapMaker: FileOpener

    init(inner: Command, fdMapMaker: @escaping FileOpener) {
        self.inner = inner
        self.fdMapMaker = fdMapMaker
    }

    convenience init(inner: Command, opening path: String, toHandle dstFd: Int32, oflag: Int32) {
        self.init(inner: inner) { command in
            let fd = open(path, oflag, 0o666)
            guard fd >= 0 else {
                return .failure(SyscallError(name: "open(\"\(path)\", ...)", command: command, error: errno))
            }
            let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
            return .success(fdMap: [(src: fd, dst: dstFd)], ref: handle)
        }
    }

    struct Result: CommandResult {
        let innerResult: CommandResult
        let command: Command
        let ref: Any?

        var isRunning: Bool { innerResult.isRunning }
        func exitCode() -> Int32 { innerResult.exitCode() }
        func succeed() throws { try innerResult.succeed() }
    }

    func coreAsync(fdMap incoming: FDMap) -> CommandResult {
        switch fdMapMaker(self) {
        case .success(let fdMap, let ref):
            return Result(
                innerResult: inner.coreAsync(fdMap: fdMap + incoming),
                command: self,
                ref: ref
            )
        case .failure(let result):
            return result
        }
    }
}

public extension Command {
    // MARK: - Output redirection

    /// Bind output to a file. Similar to ">" in bash, but will not overwrite the file
    /// - Parameter path: Path to write output to
    /// - Parameter fd: File descriptor to bind. Defaults to stdout
    func output(creatingFile path: String, fd: Int32 = STDOUT_FILENO) -> Command {
        FDWrapperCommand(inner: self, opening: path, toHandle: fd, oflag: O_CREAT | O_EXCL | O_WRONLY)
    }

    /// Bind output to a file, creating if needed. Similar to ">" in bash
    /// - Parameter path: Path to write output to
    /// - Parameter fd: File descriptor to bind. Defaults to stdout
    func output(overwritingFile path: String, fd: Int32 = STDOUT_FILENO) -> Command {
        FDWrapperCommand(inner: self, opening: path, toHandle: fd, oflag: O_CREAT | O_TRUNC | O_WRONLY)
    }

    /// Bind output to end of a file. Similar to ">>" in bash
    /// - Parameter path: Path to write output to
    /// - Parameter fd: File descriptor to bind. Defaults to stdout
    /// - Parameter createFile: fail if the file doesn't exist
    /// - Throws: FileDoesntExist if createFile is false, and the file doesn't exist
    func append(toFile path: String, fd: Int32 = STDOUT_FILENO, createFile: Bool = true) -> Command {
        var flags = O_APPEND | O_WRONLY
        if createFile {
            flags |= O_CREAT
        }
        return FDWrapperCommand(inner: self, opening: path, toHandle: fd, oflag: flags)
    }

    // MARK: - Input

    /// Bind stdin to contents of string
    /// - Parameter encoding: how encoding the outgoing data
    /// - Parameter fd: File descriptor to bind. Defaults to stdin
    /// - Throws
    func input(_ string: String, encoding: String.Encoding = .utf8, fd: Int32 = STDIN_FILENO) throws -> Command {
        guard let data = string.data(using: encoding) else {
            throw StringEncodingError(string: string, encoding: encoding)
        }
        return input(data, fd: fd)
    }

    /// Bind stdin to contents of data
    /// - Parameter fd: File descriptor to bind. Defaults to stdin
    func input(_ data: Data, fd: Int32 = STDIN_FILENO) -> Command {
        FDWrapperCommand(inner: self) { command in
            let pipe = Pipe()
            let dispatchData = data.withUnsafeBytes { DispatchData(bytes: $0) }
            let writeHandle = pipe.fileHandleForWriting
            DispatchIO.write(
                toFileDescriptor: writeHandle.fileDescriptor,
                data: dispatchData,
                runningHandlerOn: DispatchQueue.global()
            ) { [weak writeHandle] _, _ in
                writeHandle?.closeFile()
            }
            return .success(fdMap: [(src: pipe.fileHandleForReading.fileDescriptor, dst: fd)], ref: pipe)
        }
    }

    /// Bind stdin to the the JSON representation of a JSON-like value
    /// - Parameter json: Anything `JSONSerialization` can deal with
    /// - Parameter fd: File descriptor to bind. Defaults to stdin
    /// - Throws: if encoding fails
    func input(
        withJSONObject json: Any,
        fd: Int32 = STDIN_FILENO,
        options: JSONSerialization.WritingOptions = .fragmentsAllowed
    ) throws -> Command {
        input(try JSONSerialization.data(withJSONObject: json, options: options), fd: fd)
    }

    /// Bind stdin to the the JSON representation of a JSON-encodable value
    /// - Parameter object: The object to be encoded and sent
    /// - Parameter fd: File descriptor to bind. Defaults to stdin
    /// - Parameter encoder: JSONEncoder to use
    /// - Throws: if encoding fails
    func inputJSON<E : Encodable>(
        from object: E,
        fd: Int32 = STDIN_FILENO,
        encoder: JSONEncoder = .init()
    ) throws -> Command {
        input(try encoder.encode(object), fd: fd)
    }

    /// Bind stdin to a file, similar to `< file` in bash
    /// - Parameter fd: File descriptor to bind. Defaults to stdin
    func input(fromFile path: String, fd: Int32 = STDIN_FILENO) -> Command {
        FDWrapperCommand(inner: self, opening: path, toHandle: fd, oflag: O_RDONLY)
    }
}
