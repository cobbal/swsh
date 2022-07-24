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

    convenience init(inner: Command, opening path: String, toHandle dstFd: FileDescriptor, oflag: Int32) {
        self.init(inner: inner) { command in
            let fd = open(path, oflag, 0o666)
            guard fd >= 0 else {
                return .failure(SyscallError(name: "open(\"\(path)\", ...)", command: command, errno: errno))
            }
            let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
            return .success(fdMap: [dstFd: FileDescriptor(fd)], ref: handle)
        }
    }

    struct Result: CommandResult, AsyncCommandResult {
        let innerResult: CommandResult
        let command: Command
        let ref: Any?

        var isRunning: Bool { innerResult.isRunning }
        func exitCode() -> Int32 { innerResult.exitCode() }
        func succeed() throws { try innerResult.succeed() }
        func kill(signal: Int32) throws { try innerResult.kill(signal: signal) }

        #if compiler(>=5.5) && canImport(_Concurrency)
        @available(macOS 10.15, *)
        func asyncFinish() async {
            await innerResult.asyncFinishInternal()
        }
        #endif
    }

    func coreAsync(fdMap incoming: FDMap) -> CommandResult {
        switch fdMapMaker(self) {
        case let .success(fdMap, ref):
            return Result(
                innerResult: inner.coreAsync(fdMap: incoming.compose(fdMap)),
                command: self,
                ref: ref
            )
        case let .failure(result):
            return result
        }
    }
}

extension FDWrapperCommand: CustomStringConvertible {
    var description: String {
        String(describing: inner)
    }
}

extension Command {
    // MARK: - Output redirection

    /// Bind output to a file. Similar to ">" in bash, but will not overwrite the file
    /// - Parameter path: Path to write output to
    /// - Parameter fd: File descriptor to bind. Defaults to stdout
    public func output(creatingFile path: String, fd: FileDescriptor = .stdout) -> Command {
        FDWrapperCommand(inner: self, opening: path, toHandle: fd, oflag: O_CREAT | O_EXCL | O_WRONLY)
    }

    /// Bind output to a file, creating if needed. Similar to ">" in bash
    /// - Parameter path: Path to write output to
    /// - Parameter fd: File descriptor to bind. Defaults to stdout
    public func output(overwritingFile path: String, fd: FileDescriptor = .stdout) -> Command {
        FDWrapperCommand(inner: self, opening: path, toHandle: fd, oflag: O_CREAT | O_TRUNC | O_WRONLY)
    }

    /// Bind output to end of a file. Similar to ">>" in bash
    /// - Parameter path: Path to write output to
    /// - Parameter fd: File descriptor to bind. Defaults to stdout
    /// - Parameter createFile: fail if the file doesn't exist
    /// - Throws: FileDoesntExist if createFile is false, and the file doesn't exist
    public func append(toFile path: String, fd: FileDescriptor = .stdout, createFile: Bool = true) -> Command {
        var flags = O_APPEND | O_WRONLY
        if createFile {
            flags |= O_CREAT
        }
        return FDWrapperCommand(inner: self, opening: path, toHandle: fd, oflag: flags)
    }

    /// Duplicate a file handle. In bash, this is expressed like "2>&1". See also dup2(2)
    /// - Parameter srcFd: File descriptor to duplicate
    /// - Parameter dstFd: Descriptor of new, duplicated handle
    public func duplicateFd(source srcFd: FileDescriptor, destination dstFd: FileDescriptor) -> Command {
        FDWrapperCommand(inner: self) { _ in
            .success(fdMap: [dstFd: srcFd], ref: nil)
        }
    }

    /// Redirect standard error to standard output. "2>&1" in bash
    public var combineError: Command {
        duplicateFd(source: .stdout, destination: .stderr)
    }

    // MARK: - Input

    /// Bind stdin to contents of string
    /// - Parameter encoding: how encoding the outgoing data
    /// - Parameter fd: File descriptor to bind. Defaults to stdin
    /// - Throws
    public func input(
        _ string: String,
        encoding: String.Encoding = .utf8,
        fd: FileDescriptor = .stdin
    ) throws -> Command {
        guard let data = string.data(using: encoding) else {
            throw StringEncodingError(string: string, encoding: encoding)
        }
        return input(data, fd: fd)
    }

    /// Bind stdin to contents of data
    /// - Parameter fd: File descriptor to bind. Defaults to stdin
    public func input(_ data: Data, fd: FileDescriptor = .stdin) -> Command {
        FDWrapperCommand(inner: self) { _ in
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
            return .success(fdMap: [fd: pipe.fileHandleForReading.fd], ref: pipe)
        }
    }

    /// Bind stdin to the the JSON representation of a JSON-like value
    /// - Parameter json: Anything `JSONSerialization` can deal with
    /// - Parameter fd: File descriptor to bind. Defaults to stdin
    /// - Throws: if encoding fails
    public func input(
        withJSONObject json: Any,
        fd: FileDescriptor = .stdin,
        options: JSONSerialization.WritingOptions = .init()
    ) throws -> Command {
        input(try JSONSerialization.data(withJSONObject: json, options: options), fd: fd)
    }

    /// Bind stdin to the the JSON representation of a JSON-encodable value
    /// - Parameter object: The object to be encoded and sent
    /// - Parameter fd: File descriptor to bind. Defaults to stdin
    /// - Parameter encoder: JSONEncoder to use
    /// - Throws: if encoding fails
    public func inputJSON<E: Encodable>(
        from object: E,
        fd: FileDescriptor = .stdin,
        encoder: JSONEncoder = .init()
    ) throws -> Command {
        input(try encoder.encode(object), fd: fd)
    }

    /// Bind stdin to a file, similar to `< file` in bash
    /// - Parameter fd: File descriptor to bind. Defaults to stdin
    public func input(fromFile path: String, fd: FileDescriptor = .stdin) -> Command {
        FDWrapperCommand(inner: self, opening: path, toHandle: fd, oflag: O_RDONLY)
    }
}
