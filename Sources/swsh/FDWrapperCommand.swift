//
//  FDWrapperCommand.swift
//
//
//  Created by Andrew Cobb on 12/26/19.
//

import Foundation
#if os(Windows)
import WinSDK
#endif

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
            /*
            #if os(Windows)
            let path = path == "/dev/null" ? "NUL" : path
            let fileName = path.withCString(encodedAs: UTF8.self) { _strdup($0) }
            defer { free(fileName) }
            var access = DWORD(0)
            access |= (oflag & O_RDONLY) == 0 ? 0 : DWORD(GENERIC_READ)
            access |= (oflag & O_WRONLY) == 0 ? 0 : DWORD(GENERIC_WRITE)
            access |= (oflag & O_RDWR) == 0 ? 0 : DWORD(GENERIC_READ) | DWORD(GENERIC_WRITE)
            let share = DWORD(FILE_SHARE_READ)
            var securityAttributes = SECURITY_ATTRIBUTES()
            securityAttributes.nLength = DWORD(MemoryLayout<SECURITY_ATTRIBUTES>.size)
            securityAttributes.lpSecurityDescriptor = nil
            securityAttributes.bInheritHandle = true
            let creationDisposition =
                (oflag & (O_CREAT | O_TRUNC)) != 0 ? DWORD(CREATE_ALWAYS) :
                (oflag & O_EXCL) != 0 ? DWORD(CREATE_NEW) :
                (oflag & O_CREAT) != 0 ? DWORD(OPEN_ALWAYS) :
                (oflag & O_TRUNC) != 0 ? DWORD(TRUNCATE_EXISTING) :
                DWORD(OPEN_EXISTING)
            let flags = DWORD(FILE_ATTRIBUTE_NORMAL)
            printOSCall("CreateFileA", fileName, access, share, "ptr(\(securityAttributes))", creationDisposition, flags, nil)
            let osHandle = CreateFileA(
                /* lpFileName */ fileName,
                /* dwDesiredAccess */ access,
                /* dwShareMode */ share,
                /* lpSecurityAttributes */ &securityAttributes,
                /* dwCreationDisposition */ creationDisposition,
                /* dwFlagsAndAttributes */ flags,
                /* hTemplateFile */ nil
            )
            guard osHandle != INVALID_HANDLE_VALUE else {
                return .failure(SyscallError(name: "CreateFileA(\"\(path)\", ...)", command: command, errno: errno))
            }
            printOSCall("_open_osfhandle", osHandle, 0)
            let fd = _open_osfhandle(.init(bitPattern: osHandle), 0)
            guard fd >= 0 else {
                return .failure(SyscallError(name: "_open_osfhandle(\"\(osHandle)\", ...)", command: command, errno: errno))
            }
            let io = FDFileHandle(fileDescriptor: FileDescriptor(fd), closeOnDealloc: true)
            return .success(fdMap: [dstFd: io.fileDescriptor], ref: io)
            #else
            */
            #if os(Windows)
            let path = path == "/dev/null" ? "NUL" : path
            #endif
            printOSCall("open", path, oflag, 0o666)
            let fd = open(path, oflag, 0o666)
            guard fd >= 0 else {
                return .failure(SyscallError(name: "open(\"\(path)\", ...)", command: command, errno: errno))
            }
            let io = FDFileHandle(fileDescriptor: FileDescriptor(fd), closeOnDealloc: true)
            return .success(fdMap: [dstFd: io.fileDescriptor], ref: io)
            // #endif
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
            #if os(Windows)
            let pipe = FDPipe()
            let queue = DispatchQueue(label: "swsh.FDWrapperCommand.input.\(UUID().uuidString)")
            queue.async {
                do {
                    try pipe.fileHandleForWriting.handle.write(contentsOf: data)
                } catch {
                    print("Failed to write to FD \(pipe.fileHandleForWriting.fileDescriptor.rawValue). Error: \(error)")
                }
                pipe.fileHandleForWriting.close()
            }
            return .success(
                fdMap: [fd: pipe.fileHandleForReading.fileDescriptor],
                ref: pipe.fileHandleForReading
            )
            #else
            let pipe = FDPipe()
            let dispatchData = data.withUnsafeBytes { DispatchData(bytes: $0) }
            
            printOSCall("DispatchIO.write", pipe.fileHandleForWriting.fileDescriptor.rawValue, data, "DispatchQueue.global()")
            DispatchIO.write(
                toFileDescriptor: pipe.fileHandleForWriting.fileDescriptor.rawValue,
                data: dispatchData,
                runningHandlerOn: DispatchQueue.global()
            ) { [pipe = pipe] _, error in
                if error != 0 {
                    print("Failed to write to FD \(pipe.fileHandleForWriting.fileDescriptor.rawValue). Error: \(error)")
                }
                pipe.fileHandleForWriting.close()
            }
            return .success(
                fdMap: [fd: pipe.fileHandleForReading.fileDescriptor],
                ref: pipe.fileHandleForReading
            )
            #endif
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
