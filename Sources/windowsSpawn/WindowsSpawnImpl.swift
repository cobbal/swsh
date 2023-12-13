import Foundation
import WinSDK

// Adapted from libuv:
// https://github.com/libuv/libuv/blob/00357f87328def30a32af82c841e5d1667a2a827/src/win/process.c

public enum WindowsSpawnImpl {
    public enum Error: Swift.Error {
        case allocationError
        case tooManyHandles
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
        let handles: [(flags: UInt8, handle: HANDLE)]
        let count: Int
        let buffer: UnsafeMutableRawBufferPointer

        private let intSize = MemoryLayout<Int>.size
        private let byteSize = MemoryLayout<UInt8>.size
        private let ptrSize = MemoryLayout<UnsafeRawPointer>.size

        private init?(_ handles: [(flags: UInt8, handle: HANDLE)]) {
            self.handles = handles
            count = handles.count
            let byteLength = intSize + byteSize * count + ptrSize * count
            guard byteLength < UInt16.max else { return nil }

            buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: byteLength, alignment: 16)

            buffer.storeBytes(of: count, toByteOffset: 0, as: Int.self)
            for (i, handle) in handles.enumerated() {
                buffer.storeBytes(of: handle.flags, toByteOffset: intSize + byteSize * i, as: UInt8.self)
                buffer.storeBytes(of: handle.handle, toByteOffset: intSize + byteSize * count + ptrSize * i, as: HANDLE.self)
            }
        }

        static func create(_ handles: [(flags: UInt8, handle: HANDLE)]) -> Result<ChildHandleBuffer, Error> {
            guard let buffer = ChildHandleBuffer(handles) else { return .failure(.tooManyHandles) }
            return .success(buffer)
        }

        subscript(index: Int) -> HANDLE? {
            guard index < count else { return INVALID_HANDLE_VALUE }
            return buffer.loadUnaligned(fromByteOffset: intSize + byteSize * count + ptrSize * index, as: HANDLE.self)
        }

        deinit {
            buffer.deallocate()
        }
    }

    public static func spawn(
        command: String,
        arguments: [String],
        env: [String: String],
        fdMap: [Int32: Int32],
        pathResolve: Bool
    ) -> Result<PROCESS_INFORMATION, Error> {
        print("Windows Command: \(command) \(arguments.joined(separator: " "))\n")

        guard let command = command.withCString(encodedAs: UTF16.self, _wcsdup) else {
            return .failure(.allocationError) 
        }
        defer { free(command) }
        // TODO: Joining with spaces is terrible!! Do real quoting.
        guard let arguments = arguments.joined(separator: " ").withCString(encodedAs: UTF16.self, _wcsdup) else {
            return .failure(.allocationError)
        }
        defer { free(arguments) }
        
        var startup = STARTUPINFOW()
        var info = PROCESS_INFORMATION()
        startup.cb = DWORD(MemoryLayout<STARTUPINFOW>.size)
        startup.dwFlags = STARTF_USESTDHANDLES

        // TODO: handles
        let handleStructure: ChildHandleBuffer
        switch ChildHandleBuffer.create([]) {
            case .success(let buffer): handleStructure = buffer
            case .failure(let error): return .failure(error)
        }

        startup.cbReserved2 = UInt16(handleStructure.buffer.count)
        startup.lpReserved2 = .init(bitPattern: UInt(bitPattern: handleStructure.buffer.baseAddress))

        startup.hStdInput = handleStructure[0]
        startup.hStdOutput = handleStructure[1]
        startup.hStdError = handleStructure[2]

        let processFlags = DWORD(CREATE_UNICODE_ENVIRONMENT | CREATE_DEFAULT_ERROR_MODE | CREATE_SUSPENDED)

        guard CreateProcessW(
            /* lpApplicationName: */ command,
            /* lpCommandLine: */ arguments,
            /* lpProcessAttributes: */ nil,
            /* lpThreadAttributes: */ nil,
            /* bInheritHandles: */ true,
            /* dwCreationFlags: */ processFlags,
            /* lpEnvironment: */ nil, // TODO
            /* lpCurrentDirectory: */ nil, // TODO
            /* lpStartupInfo: */ &startup,
            /* lpProcessInformation: */ &info
        ) else { 
            let err = GetLastError()
            return .failure(Error("CreateProcessW failed: ", systemError: err))
        }
        // defer {
        //     CloseHandle(info.hThread)
        // }

        return .success(info)
    }
}
