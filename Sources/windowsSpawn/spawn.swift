import Foundation
import WinSDK

// Adapted from libuv:
// https://github.com/libuv/libuv/blob/00357f87328def30a32af82c841e5d1667a2a827/src/win/process.c

enum WindowsSpawnError: Error {
    case TooManyHandles
    case SystemError(DWORD)
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

    init(_ handles: [(flags: UInt8, handle: HANDLE)]) throws {
        self.handles = handles
        count = handles.count
        let byteLength = intSize + byteSize * count + ptrSize * count
        guard byteLength < UInt16.max else { throw WindowsSpawnError.TooManyHandles }

        buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: byteLength, alignment: 16)

        buffer.storeBytes(of: count, toByteOffset: 0, as: Int.self)
        for (i, handle) in handles.enumerated() {
            buffer.storeBytes(of: handle.flags, toByteOffset: intSize + byteSize * i, as: UInt8.self)
            buffer.storeBytes(of: handle.handle, toByteOffset: intSize + byteSize * count + ptrSize * i, as: HANDLE.self)
        }
    }

    subscript(index: Int) -> HANDLE? {
        guard index < count else { return INVALID_HANDLE_VALUE }
        return buffer.loadUnaligned(fromByteOffset: intSize + byteSize * count + ptrSize * index, as: HANDLE.self)
    }

    deinit {
        buffer.deallocate()
    }
}

func spawn(
    command: String,
    arguments: [String],
    env: [String: String],
    fdMap: [Int: Int],
    pathResolve: Bool
) throws -> Int? {
    guard let command = command.withCString(encodedAs: UTF16.self, _wcsdup) else { return nil }
    defer { free(command) }
    guard let arguments = "TODO".withCString(encodedAs: UTF16.self, _wcsdup) else { return nil }
    defer { free(arguments) }

    var startup = STARTUPINFOW()
    var info = PROCESS_INFORMATION()
    startup.cb = DWORD(MemoryLayout<STARTUPINFOW>.size)
    startup.dwFlags = STARTF_USESTDHANDLES

    // TODO: handles
    let handleStructure = try ChildHandleBuffer([])

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
        throw WindowsSpawnError.SystemError(GetLastError())
    }

    guard ResumeThread(info.hThread) != DWORD(bitPattern: -1) else {
        let err = GetLastError();
        TerminateProcess(info.hProcess, 1);
        throw WindowsSpawnError.SystemError(err);
    }

    return Int(info.dwProcessId);
}