#if canImport(ucrt)

import ucrt
import Foundation
import windowsSpawn
import WinSDK

/// A process spawned with `CreateProcessW`
struct WindowsSpawn: ProcessSpawner {
    public enum Error: Swift.Error {
        case systemError(String, DWORD)
    }

    public func spawn(
        command: String,
        arguments: [String],
        env: [String: String],
        fdMap: FDMap,
        pathResolve: Bool
    ) -> SpawnResult {
        let intFDMap = Dictionary(uniqueKeysWithValues: fdMap.map { ($0.key.rawValue, $0.value.rawValue) })
        do {
            switch WindowsSpawnImpl.spawn(
                command: command,
                arguments: arguments,
                env: env,
                fdMap: intFDMap,
                pathResolve: pathResolve
            ) {
                case .success(let info): 
                    let process = ProcessInformation(
                        command: command,
                        arguments: arguments,
                        env: env,
                        id: Int(info.dwProcessId), 
                        handle: info.hProcess, 
                        mainThreadHandle: info.hThread
                    )
                    return .success(process)
                case .failure(let error): 
                    // TODO: Can pass error context string along somehow?
                    print(error)
                    return .error(errno: error.errno)
            }
        }
    }

    public func reapAsync(
        process: ProcessInformation,
        queue: DispatchQueue,
        callback: @escaping (Int32) -> Void
    ) {
        queue.async {
            WaitForSingleObject(process.handle, INFINITE)
          
            var exitCode: DWORD = 0
            guard GetExitCodeProcess(process.handle, &exitCode) != false else {
                callback(Int32(bitPattern: DWORD(GetLastError()))) // TODO: What should this be if the exit code cannot be determined?
                return
            }

            CloseHandle(process.mainThreadHandle)
            CloseHandle(process.handle)

            callback(Int32(bitPattern: exitCode))
        }
    }

    public func resume(
        process: ProcessInformation
    ) throws {
        guard ResumeThread(process.mainThreadHandle) != DWORD(bitPattern: -1) else {
            let err = GetLastError()
            TerminateProcess(process.handle, 1)
            throw Error.systemError("Resuming process failed: ", err)
        }
    }
}

// Adapted from libuv:
// https://github.com/libuv/libuv/blob/00357f87328def30a32af82c841e5d1667a2a827/src/win/process.c
public enum WindowsSpawnImpl {
    public enum Error: Swift.Error {
        case allocationError
        case tooManyHandles
        case envPathUnset
        case systemError(DWORD, String)

        init(_ context: String = "", systemError: DWORD) {
            var messageBuffer: LPWSTR?
            // This call is terrible because the type of the pointer depends on the first argument to the call
            let size = withUnsafeMutableBytes(of: &messageBuffer) { bufferPtr in
                FormatMessageW(
                    DWORD(FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS),
                    nil,
                    systemError,
                    .init(bitPattern: 0),
                    bufferPtr.baseAddress!.assumingMemoryBound(to: WCHAR.self),
                    0,
                    nil
                )
            }
            guard size > 0, let messageBuffer = messageBuffer else {
                self = .systemError(systemError, "\(context)Unknown error \(systemError)")
                return
            }
            defer { LocalFree(messageBuffer) }
            self = .systemError(systemError, context + String(utf16CodeUnits: messageBuffer, count: Int(size)))
        }

        public var errno: Int32 {
            switch self {
                case .systemError(let errno, _): return Int32(errno)
                default: return -1
            }
        }
    }

    // Adapted from libuv:
    // https://github.com/libuv/libuv/blob/00357f87328def30a32af82c841e5d1667a2a827/src/win/process-stdio.c
    /*
    * The `child_stdio_buffer` buffer has the following layout:
    *   int number_of_fds
    *   unsigned char crt_flags[number_of_fds]
    *   // [cobbal] no alignment?
    *   HANDLE os_handle[number_of_fds]
    */
    class ChildHandleBuffer {
        let shouldDuplicate = false

        let handles: [(flags: UInt8, handle: HANDLE?)]
        let count: Int
        let buffer: UnsafeMutableRawBufferPointer

        private let intSize = MemoryLayout<Int>.size
        private let byteSize = MemoryLayout<UInt8>.size
        private let ptrSize = MemoryLayout<UnsafeRawPointer>.size

        static func create(_ handles: [HANDLE?]) -> Result<ChildHandleBuffer, Error> {
            let flaggedHandles: [(flags: UInt8, handle: HANDLE?)] = handles.map { handle in
                let FOPEN: UInt8 = 0x01
                // let FEOFLAG: UInt8 = 0x02
                // let FCRLF: UInt8 = 0x04
                let FPIPE: UInt8 = 0x08
                // let FNOINHERIT: UInt8 = 0x10
                // let FAPPEND: UInt8 = 0x20
                let FDEV: UInt8 = 0x40
                // let FTEXT: UInt8 = 0x80

                let fileType = GetFileType(handle)
                let flags: UInt8
                switch Int32(fileType) {
                case FILE_TYPE_DISK: 
                    flags = FOPEN
                case FILE_TYPE_PIPE: 
                    flags = FOPEN | FPIPE
                case FILE_TYPE_CHAR,
                    FILE_TYPE_REMOTE:
                    flags = FOPEN | FDEV
                case FILE_TYPE_UNKNOWN:
                    // TODO: What if GetFileType returns an error?
                    flags = FOPEN | FDEV
                default:
                    preconditionFailure("Windows lied about the file type. Should not happen.")
                }

                return (flags: flags, handle: handle)
            }

            guard let buffer = ChildHandleBuffer(flaggedHandles) else { return .failure(.tooManyHandles) }
            return .success(buffer)
        }

        private init?(_ handles: [(flags: UInt8, handle: HANDLE?)]) {
            self.handles = !shouldDuplicate ? handles : handles.map { (flags: $0.flags, handle: Self.duplicate(handle: $0.handle)) }
            count = handles.count
            let byteLength = intSize + byteSize * count + ptrSize * count
            guard byteLength < UInt16.max else { return nil }

            buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: byteLength, alignment: 16)

            buffer.storeBytes(of: count, toByteOffset: 0, as: Int.self)
            for (i, handle) in handles.enumerated() {
                buffer.storeBytes(of: handle.flags, toByteOffset: intSize + byteSize * i, as: UInt8.self)
                buffer.storeBytes(of: handle.handle, toByteOffset: intSize + byteSize * count + ptrSize * i, as: HANDLE?.self)
            }
        }

        subscript(index: Int) -> HANDLE? {
            guard index < count else { return INVALID_HANDLE_VALUE }
            return buffer.loadUnaligned(fromByteOffset: intSize + byteSize * count + ptrSize * index, as: HANDLE.self)
        }

        deinit {
            // Close all handles that were duplicated
            if shouldDuplicate {
                for index in 0..<count {
                    let handle = self[index]
                    if handle != INVALID_HANDLE_VALUE {
                        CloseHandle(handle)
                    }
                }
            }

            buffer.deallocate()
        }
    
        // Adaped from libuv: 
        // https://github.com/libuv/libuv/blob/00357f87328def30a32af82c841e5d1667a2a827/src/win/process-stdio.c#L96
        private static func duplicate(handle: HANDLE?) -> HANDLE? {
            guard handle != INVALID_HANDLE_VALUE, handle != nil, handle != HANDLE(bitPattern: -2) else {
                return nil
            }

            let currentProcess = GetCurrentProcess()
            var duplicated: HANDLE?
            guard DuplicateHandle(
                currentProcess,
                handle,
                currentProcess,
                &duplicated,
                0,
                true,
                DWORD(DUPLICATE_SAME_ACCESS)
            ) else {
                return nil
            }
            return duplicated
        }

        public static func duplicateStdin() -> HANDLE? {
            Self.duplicate(handle: GetStdHandle(STD_INPUT_HANDLE))
        }

        public static func duplicateStdout() -> HANDLE? {
            Self.duplicate(handle: GetStdHandle(STD_OUTPUT_HANDLE))
        }

        public static func duplicateStderr() -> HANDLE? {
            Self.duplicate(handle: GetStdHandle(STD_ERROR_HANDLE))
        }
    }

    // Adapted from libuv:
    // https://github.com/libuv/libuv/blob/00357f87328def30a32af82c841e5d1667a2a827/src/win/process.c#L934
    public static func spawn(
        command: String,
        arguments: [String],
        env: [String: String],
        fdMap: [Int32: Int32],
        pathResolve: Bool
    ) -> Result<PROCESS_INFORMATION, Error> {
        // Find the path environment variable, checking the passed environment first, then the system environment
        guard let envPath = env.keys.first(where:) { $0.uppercased == "PATH" }.map({ env[$0]! }) else {
            return .failure(Error.envPathUnset)
        }
        let path: UnsafeMutablePointer<wchar_t>? = envPath.withCString(encodedAs: UTF16.self, _wcsdup)
        defer { free(path) }
        print("path: \(path.map { String(utf16CodeUnits: $0, count: wcslen($0)) } ?? "")")
        
        // Find the current working directory
        let cwdLength = GetCurrentDirectoryW(0, nil)
        guard cwdLength > 0 else {
            return .failure(Error("Could not find current working directory", systemError: DWORD(GetLastError())))
        }
        let cwd: UnsafeMutablePointer<wchar_t>? = calloc(MemoryLayout<wchar_t>.size, Int(cwdLength)).assumingMemoryBound(to: wchar_t.self)
        defer { free(cwd) }
        let r = GetCurrentDirectoryW(cwdLength, cwd)
        guard r != 0 && r < cwdLength else {
            return .failure(Error("Could not load current working directory", systemError: DWORD(GetLastError())))
        }
        print("cwd: \(cwd.map { String(utf16CodeUnits: $0, count: wcslen($0)) } ?? "")")
        
        // Search the path and working directory for the application that is to be used to execute the command, in a form sutable to use in CreateProcessW()
        let applicationPath = command.withCString(encodedAs: UTF16.self) { windowsSpawn.search_path($0, cwd, path) }
        defer { free(applicationPath) }
        guard applicationPath != nil else {
            return .failure(Error("Could not find application", systemError: DWORD(ERROR_FILE_NOT_FOUND)))
        }
        print("applicationPath: \(applicationPath.map { String(utf16CodeUnits: $0, count: wcslen($0)) } ?? "")")
        
        // Convert the command (not the application path!) and arguments to a null-terminated list of null-terminated UTF8 strings,
        // then process them into properly quoted wide strings suitable for use in CreateProcessW()
        var args = ([command] + arguments).map { _strdup($0) } + [nil]
        defer { args.forEach { free($0) } }
        var commandLine: UnsafeMutablePointer<wchar_t>?
        let makeArgsStatus = windowsSpawn.make_program_args(&args, 0, &commandLine)
        defer { free(commandLine) }
        guard makeArgsStatus == 0 else {
            return .failure(Error("Unable to convert command arguments", systemError: DWORD(makeArgsStatus)))
        }
        print("commandLine: \(commandLine.map { String(utf16CodeUnits: $0, count: wcslen($0)) } ?? "")")
        
        // Package the file descriptors map as a list of handles, 
        // then process them into a form suitable for use in the startup information object passed to CreateProcessW()
        print("fdMap: \(fdMap)")
        let handles: [Int32: HANDLE?] = fdMap.mapValues { HANDLE(bitPattern: _get_osfhandle($0)) }
        print("handles: \(handles)")
        let handleMax = fdMap.keys.max() ?? -1
        var handleArray = Array<HANDLE?>(repeating: nil, count: Int(handleMax + 1))
        for (fd, handle) in handles {
            handleArray[Int(fd)] = handle
        }
        let handleStructure: ChildHandleBuffer
        switch ChildHandleBuffer.create(handleArray) {
            case .success(let buffer): handleStructure = buffer
            case .failure(let error): return .failure(error)
        }
        var startup = STARTUPINFOW()
        startup.cb = DWORD(MemoryLayout<STARTUPINFOW>.size)
        startup.lpReserved = nil
        startup.lpDesktop = nil
        startup.lpTitle = nil
        startup.dwFlags = STARTF_USESTDHANDLES
        startup.cbReserved2 = UInt16(handleStructure.buffer.count)
        startup.lpReserved2 = .init(bitPattern: UInt(bitPattern: handleStructure.buffer.baseAddress))
        startup.hStdInput = handleStructure[0]
        startup.hStdOutput = handleStructure[1]
        startup.hStdError = handleStructure[2]

        print("startup.hStdInput: \(startup.hStdInput)")
        print("startup.hStdOutput: \(startup.hStdOutput)")
        print("startup.hStdError: \(startup.hStdError)")
        
        // Spawn a child process to execute the desired command, requesting that it be in a suspended state to be resumed later
        var info = PROCESS_INFORMATION()
        guard CreateProcessW(
            /* lpApplicationName: */ applicationPath,
            /* lpCommandLine: */ commandLine,
            /* lpProcessAttributes: */ nil,
            /* lpThreadAttributes: */ nil,
            /* bInheritHandles: */ true,
            /* dwCreationFlags: */ DWORD(CREATE_UNICODE_ENVIRONMENT | CREATE_DEFAULT_ERROR_MODE | CREATE_SUSPENDED),
            /* lpEnvironment: */ nil, // TODO
            /* lpCurrentDirectory: */ cwd,
            /* lpStartupInfo: */ &startup,
            /* lpProcessInformation: */ &info
        ) else { 
            return .failure(Error("CreateProcessW failed: ", systemError: DWORD(GetLastError())))
        }
        
        return .success(info)
    }
}

#endif
