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
        let handles: [(flags: UInt8, handle: HANDLE?)]
        let count: Int
        let buffer: UnsafeMutableRawBufferPointer

        private let intSize = MemoryLayout<Int>.size
        private let byteSize = MemoryLayout<UInt8>.size
        private let ptrSize = MemoryLayout<UnsafeRawPointer>.size

        private init?(_ handles: [(flags: UInt8, handle: HANDLE?)]) {
            self.handles = handles
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

        static func create(_ handles: [(flags: UInt8, handle: HANDLE?)]) -> Result<ChildHandleBuffer, Error> {
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

    // Adaped from libuv: 
    // https://github.com/libuv/libuv/blob/00357f87328def30a32af82c841e5d1667a2a827/src/win/process-stdio.c#L96
    private static func duplicate(fd: HANDLE?) -> HANDLE? {
        guard fd != INVALID_HANDLE_VALUE, fd != nil, fd != HANDLE(bitPattern: -2) else {
            return nil
        }

        let currentProcess = GetCurrentProcess()
        var duplicated: HANDLE?
        guard DuplicateHandle(
            currentProcess,
            fd,
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
        Self.duplicate(fd: GetStdHandle(STD_INPUT_HANDLE))
    }

    public static func duplicateStdout() -> HANDLE? {
        Self.duplicate(fd: GetStdHandle(STD_OUTPUT_HANDLE))
    }

    public static func duplicateStderr() -> HANDLE? {
        Self.duplicate(fd: GetStdHandle(STD_ERROR_HANDLE))
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
        guard let command = command.withCString(encodedAs: UTF16.self, _wcsdup) else {
            return .failure(.allocationError) 
        }
        defer { free(command) }
        // TODO: Joining with spaces is terrible!! Do real quoting.
        guard let arguments = arguments.joined(separator: " ").withCString(encodedAs: UTF16.self, _wcsdup) else {
            return .failure(.allocationError)
        }
        defer { free(arguments) }
        
        let handles: [Int32: HANDLE?] = fdMap.mapValues { HANDLE(bitPattern: _get_osfhandle($0)) }
        let handleMax = fdMap.keys.max() ?? -1
        var handleArray = Array<(flags: UInt8, handle: HANDLE?)>(repeating: (flags: 0, handle: nil), count: Int(handleMax + 1))
        for (fd, handle) in handles {
            let FOPEN: UInt8 = 0x01
            let FEOFLAG: UInt8 = 0x02
            let FCRLF: UInt8 = 0x04
            let FPIPE: UInt8 = 0x08
            let FNOINHERIT: UInt8 = 0x10
            let FAPPEND: UInt8 = 0x20
            let FDEV: UInt8 = 0x40
            let FTEXT: UInt8 = 0x80

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

            handleArray[Int(fd)] = (flags: flags, handle: handle)
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

        print("handleArray: \(handleArray)")
        print("startup.hStdInput: \(startup.hStdInput)")
        print("startup.hStdOutput: \(startup.hStdOutput)")
        print("startup.hStdError: \(startup.hStdError)")

        var chars: [wchar_t] = [wchar_t(UnicodeScalar("s").value), wchar_t(UnicodeScalar("u").value), wchar_t(UnicodeScalar("p").value), wchar_t(UnicodeScalar("\0").value)]
        let charsCopy = _wcsdup(chars)
        defer { free(charsCopy) }
        
        let length = wcslen(charsCopy)
        print("length: \(length)")
        
        // var written = DWORD(0)
        // WriteFile(startup.hStdOutput, &chars, DWORD(chars.count * MemoryLayout<wchar_t>.size), &written, nil)

        var info = PROCESS_INFORMATION()
        guard CreateProcessW(
            /* lpApplicationName: */ command,
            /* lpCommandLine: */ charsCopy,//arguments,
            /* lpProcessAttributes: */ nil,
            /* lpThreadAttributes: */ nil,
            /* bInheritHandles: */ true,
            /* dwCreationFlags: */ DWORD(CREATE_UNICODE_ENVIRONMENT | CREATE_DEFAULT_ERROR_MODE | CREATE_SUSPENDED | CREATE_NO_WINDOW),
            /* lpEnvironment: */ nil, // TODO
            /* lpCurrentDirectory: */ nil, // TODO
            /* lpStartupInfo: */ &startup,
            /* lpProcessInformation: */ &info
        ) else { 
            let err = GetLastError()
            return .failure(Error("CreateProcessW failed: ", systemError: err))
        }

        // TODO: Cleanup stdio handles

        return .success(info)
    }
}
