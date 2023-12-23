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
            print("Spawning: \(command) \(arguments.joined(separator: " "))")
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
                    print("Spawned: \(command) \(arguments.joined(separator: " "))")
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
            printOSCall("WaitForSingleObject", process.handle, "INFINITE")
            WaitForSingleObject(process.handle, INFINITE)
          
            var exitCode: DWORD = 0
            printOSCall("GetExitCodeProcess", process.handle, "ptr(\(exitCode))")
            guard GetExitCodeProcess(process.handle, &exitCode) != false else {
                callback(Int32(bitPattern: DWORD(GetLastError()))) // TODO: What should this be if the exit code cannot be determined?
                return
            }

            printOSCall("CloseHandle", process.mainThreadHandle)
            CloseHandle(process.mainThreadHandle)
            printOSCall("CloseHandle", process.handle)
            CloseHandle(process.handle)
            print("Reaped(\(exitCode)): \(process)")

            callback(Int32(bitPattern: exitCode))
        }
    }

    public func resume(
        process: ProcessInformation
    ) throws {
        printOSCall("ResumeThread", process.mainThreadHandle)
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
        private let shouldDuplicate = true
        private let intSize = MemoryLayout<Int>.size
        private let byteSize = MemoryLayout<UInt8>.size
        private let ptrSize = MemoryLayout<UnsafeRawPointer>.size

        let handles: [HANDLE?]
        let buffer: UnsafeMutableRawBufferPointer
        let count: Int
        
        static func create(_ fdMap: [Int32: Int32]) -> Result<ChildHandleBuffer, Error> {
            let parentFDMax = fdMap.keys.max() ?? -1
            var childHandleArray = Array<HANDLE?>(repeating: nil, count: Int(parentFDMax + 1))
            for (parentFD, childFD) in fdMap {
                childHandleArray[Int(parentFD)] = Self.osHandle(for: childFD)
            }

            guard let buffer = ChildHandleBuffer(childHandleArray) else { return .failure(.tooManyHandles) }
            return .success(buffer)
        }

        private init?(_ handles: [HANDLE?]) {
            let handles = !shouldDuplicate ? handles : handles.map { Self.duplicate($0) }
            let count = handles.count

            // Pack the handles into a buffer suitable for passing to CreateProcessW
            let byteLength = intSize + byteSize * count + ptrSize * count
            guard byteLength < UInt16.max else { return nil }
            buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: byteLength, alignment: 16)
            buffer.storeBytes(of: count, toByteOffset: 0, as: Int.self)
            for i in 0..<count {
                let handle = handles[i]
                let flags = Self.flags(for: handle)
                buffer.storeBytes(of: flags, toByteOffset: intSize + byteSize * i, as: UInt8.self)
                buffer.storeBytes(of: handle, toByteOffset: intSize + byteSize * count + ptrSize * i, as: HANDLE?.self)
            }

            self.handles = handles
            self.count = count
        }

        subscript(index: Int) -> HANDLE? {
            guard index < count else { return INVALID_HANDLE_VALUE }
            return buffer.loadUnaligned(fromByteOffset: intSize + byteSize * count + ptrSize * index, as: HANDLE.self)
        }

        deinit {
            if shouldDuplicate {
                for handle in handles {
                    if let handle = handle {
                        printOSCall("CloseHandle", handle)
                        CloseHandle(handle)
                        print("Closed \(handle)")
                    }
                }
            }
            buffer.deallocate()
        }

        // Adapted from libuv:
        // https://github.com/libuv/libuv/blob/1479b76310a38d98eda94db2b7f8a40e04b3ff32/src/win/handle-inl.h#L166
        private static func osHandle(for fileDescriptor: Int32) -> HANDLE? {
            // TODO: Can disable assert-in-debug-builds-only nonsense for _get_osfhandle()?
            printOSCall("_get_osfhandle", fileDescriptor)
            return HANDLE(bitPattern: _get_osfhandle(fileDescriptor))
        }
    
        // Adapted from libuv:
        // https://github.com/libuv/libuv/blob/1479b76310a38d98eda94db2b7f8a40e04b3ff32/src/win/process-stdio.c#L273
        private static func flags(for handle: HANDLE?) -> UInt8 {
            let FOPEN: UInt8 = 0x01
            // let FEOFLAG: UInt8 = 0x02
            // let FCRLF: UInt8 = 0x04
            let FPIPE: UInt8 = 0x08
            // let FNOINHERIT: UInt8 = 0x10
            // let FAPPEND: UInt8 = 0x20
            let FDEV: UInt8 = 0x40
            // let FTEXT: UInt8 = 0x80

            printOSCall("GetFileType", handle)
            switch Int32(GetFileType(handle)) {
            case FILE_TYPE_DISK: return FOPEN
            case FILE_TYPE_PIPE: return FOPEN | FPIPE
            case FILE_TYPE_CHAR: return FOPEN | FDEV
            case FILE_TYPE_REMOTE: return FOPEN | FDEV
            case FILE_TYPE_UNKNOWN: return FOPEN | FDEV // TODO: What if GetFileType returns an error?
            default: preconditionFailure("Windows lied about the file type. Should not happen.")
            }
        }

        // Adaped from libuv: 
        // https://github.com/libuv/libuv/blob/00357f87328def30a32af82c841e5d1667a2a827/src/win/process-stdio.c#L96
        private static func duplicate(_ handle: HANDLE?) -> HANDLE? {
            guard handle != INVALID_HANDLE_VALUE, handle != nil, handle != HANDLE(bitPattern: -2) else {
                return nil
            }

            printOSCall("GetCurrentProcess")
            let currentProcess = GetCurrentProcess()
            var duplicated: HANDLE?
            printOSCall("DuplicateHandle", currentProcess, handle, currentProcess, "ptr(out)", 0, true, "DUPLICATE_SAME_ACCESS")
            guard DuplicateHandle(
                /* hSourceProcessHandle: */ currentProcess,
                /* hSourceHandle: */ handle,
                /* hTargetProcessHandle: */ currentProcess,
                /* lpTargetHandle: */ &duplicated,
                /* dwDesiredAccess: */ 0,
                /* bInheritHandle: */ true,
                /* dwOptions: */ DWORD(DUPLICATE_SAME_ACCESS)
            ) else {
                return nil
            }
            print("Duplicated \(String(describing: handle)) to \(String(describing: duplicated))")
            
            return duplicated
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
        guard let envPath = env.keys.first(where: { $0.uppercased == "PATH" }).map({ env[$0]! }) else {
            return .failure(Error.envPathUnset)
        }
        let path: UnsafeMutablePointer<wchar_t>? = envPath.withCString(encodedAs: UTF16.self, _wcsdup)
        defer { free(path) }
        // print("path: \(path.map { String(utf16CodeUnits: $0, count: wcslen($0)) } ?? "")")
        
        // Find the current working directory
        printOSCall("GetCurrentDirectoryW", 0, nil)
        let cwdLength = GetCurrentDirectoryW(0, nil)
        guard cwdLength > 0 else {
            return .failure(Error("Could not find current working directory", systemError: DWORD(GetLastError())))
        }
        let cwd: UnsafeMutablePointer<wchar_t>? = calloc(MemoryLayout<wchar_t>.size, Int(cwdLength)).assumingMemoryBound(to: wchar_t.self)
        defer { free(cwd) }
        printOSCall("GetCurrentDirectoryW", cwdLength, cwd)
        let r = GetCurrentDirectoryW(cwdLength, cwd)
        guard r != 0 && r < cwdLength else {
            return .failure(Error("Could not load current working directory", systemError: DWORD(GetLastError())))
        }
        // print("cwd: \(cwd.map { String(utf16CodeUnits: $0, count: wcslen($0)) } ?? "")")
        
        // Search the path and working directory for the application that is to be used to execute the command, in a form sutable to use in CreateProcessW()
        printOSCall("windowsSpawn.search_path", command, cwd, path)
        let applicationPath = command.withCString(encodedAs: UTF16.self) { windowsSpawn.search_path($0, cwd, path) }
        defer { free(applicationPath) }
        guard applicationPath != nil else {
            return .failure(Error("Could not find application", systemError: DWORD(ERROR_FILE_NOT_FOUND)))
        }
        // print("applicationPath: \(applicationPath.map { String(utf16CodeUnits: $0, count: wcslen($0)) } ?? "")")
        
        // Convert the command (not the application path!) and arguments to a null-terminated list of null-terminated UTF8 strings,
        // then process them into properly quoted wide strings suitable for use in CreateProcessW()
        var args = ([command] + arguments).map { _strdup($0) } + [nil]
        defer { args.forEach { free($0) } }
        var commandLine: UnsafeMutablePointer<wchar_t>?
        printOSCall("windowsSpawn.make_program_args", args, 0, "ptr(out)")
        let makeArgsStatus = windowsSpawn.make_program_args(&args, 0, &commandLine)
        defer { free(commandLine) }
        guard makeArgsStatus == 0 else {
            return .failure(Error("Unable to convert command arguments", systemError: DWORD(makeArgsStatus)))
        }
        // print("commandLine: \(commandLine.map { String(utf16CodeUnits: $0, count: wcslen($0)) } ?? "")")
        
        // Package the file descriptors map as a list of handles, 
        // then process them into a form suitable for use in the startup information object passed to CreateProcessW()
        // print("fdMap: \(fdMap)")
        let childHandleStructure: ChildHandleBuffer
        switch ChildHandleBuffer.create(fdMap) {
            case .success(let buffer): childHandleStructure = buffer
            case .failure(let error): return .failure(error)
        }
        print("childHandleStructure: \((0..<childHandleStructure.count).map { "(parentFD: \(fdMap[Int32($0)]!) childFD: \($0) osHandle: \(childHandleStructure[$0]!))" })")
        var startup = STARTUPINFOW()
        startup.cb = DWORD(MemoryLayout<STARTUPINFOW>.size)
        startup.lpReserved = nil
        startup.lpDesktop = nil
        startup.lpTitle = nil
        startup.dwFlags = STARTF_USESTDHANDLES
        startup.cbReserved2 = UInt16(childHandleStructure.buffer.count)
        startup.lpReserved2 = .init(bitPattern: UInt(bitPattern: childHandleStructure.buffer.baseAddress))
        startup.hStdInput = childHandleStructure[0]
        startup.hStdOutput = childHandleStructure[1]
        startup.hStdError = childHandleStructure[2]

        // Spawn a child process to execute the desired command, requesting that it be in a suspended state to be resumed later
        let creationFlags = DWORD(CREATE_UNICODE_ENVIRONMENT | CREATE_DEFAULT_ERROR_MODE | CREATE_SUSPENDED)
        var info = PROCESS_INFORMATION()
        printOSCall("CreateProcessW", applicationPath, commandLine, nil, nil, true, nil, creationFlags, nil, cwd, "ptr(\(startup))", "ptr(\(info))")
        guard CreateProcessW(
            /* lpApplicationName: */ applicationPath,
            /* lpCommandLine: */ commandLine,
            /* lpProcessAttributes: */ nil,
            /* lpThreadAttributes: */ nil,
            /* bInheritHandles: */ true,
            /* dwCreationFlags: */ creationFlags,
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
