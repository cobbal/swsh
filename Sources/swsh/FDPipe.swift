import Foundation
#if os(Windows)
import WinSDK
import ucrt
#endif

/// A version of `Pipe` that works more uniformly between windows and posix
public class FDPipe {
    public let fileHandleForReading: FDFileHandle
    public let fileHandleForWriting: FDFileHandle

    public init() {
        #if os(Windows)
        /*
        // the `pipe` system call creates two `fd` in a malloc'ed area
        let fds = UnsafeMutablePointer<Int32>.allocate(capacity: 2)
        defer { fds.deallocate() }
        // If the operating system prevents us from creating file handles, stop
        printOSCall("_pipe", 0, "_O_BINARY")
        let ret = _pipe(fds, 0, _O_BINARY)
        let fileDescriptorForReading: FileDescriptor
        let fileDescriptorForWriting: FileDescriptor
        switch (ret, errno) {
        case (0, _):
            fileDescriptorForReading = FileDescriptor(fds[0])
            fileDescriptorForWriting = FileDescriptor(fds[1])

        case (-1, EMFILE), (-1, ENFILE):
            // Unfortunately this initializer does not throw and isn't failable so this is only
            // way of handling this situation.
            fileDescriptorForReading = FileDescriptor(-1)
            fileDescriptorForWriting = FileDescriptor(-1)
 
        default:
            fatalError("Error calling pipe(): \(errno)")
        }

        fileHandleForReading = FDFileHandle(fileDescriptor: fileDescriptorForReading, closeOnDealloc: true)
        fileHandleForWriting = FDFileHandle(fileDescriptor: fileDescriptorForWriting, closeOnDealloc: true)
        */
        // Adapted from libuv:
        // https://github.com/libuv/libuv/blob/34db4c21b1f3182a74091d927b10bb9830ef6717/src/win/pipe.c#L249
        let uniquePipeName = "\\\\.\\pipe\\swsh-\(UUID().uuidString)-\(GetCurrentProcessId())"
        print("uniquePipeName: \(uniquePipeName)")
        let pipeName: UnsafeMutablePointer<CChar>? = uniquePipeName.withCString(encodedAs: UTF8.self) { _strdup($0) }
        defer { free(pipeName) }
        let pipeMode = DWORD(PIPE_TYPE_BYTE) | DWORD(PIPE_READMODE_BYTE) | DWORD(PIPE_WAIT)
        let serverAccess = 
            // DWORD(PIPE_ACCESS_INBOUND) | 
            DWORD(PIPE_ACCESS_OUTBOUND) | 
            DWORD(WRITE_DAC) | 
            DWORD(FILE_FLAG_FIRST_PIPE_INSTANCE)
        let clientAccess = 
            DWORD(GENERIC_READ) | 
            // DWORD(FILE_READ_ATTRIBUTES) |
            // DWORD(GENERIC_WRITE) |
            DWORD(FILE_WRITE_ATTRIBUTES) |
            DWORD(WRITE_DAC)
        printOSCall("CreateNamedPipeA", pipeName, serverAccess, pipeMode, 1, 65536, 65536, 0, nil)
        let serverPipe = CreateNamedPipeA(
            /* lpName */ pipeName,
            /* dwOpenMode */ serverAccess,
            /* dwPipeMode */ pipeMode,
            /* nMaxInstances */ 1,
            /* nOutBufferSize */ 65536,
            /* nInBufferSize */ 65536,
            /* nDefaultTimeOut */ 0,
            /* lpSecurityAttributes */ nil
        )
        guard serverPipe != INVALID_HANDLE_VALUE else {
            fatalError("Server pipe creation failed with error: \(WindowsSpawnImpl.Error(systemError: GetLastError()))")
        }
        
        var clientSecurityAttributes = SECURITY_ATTRIBUTES()
        clientSecurityAttributes.nLength = DWORD(MemoryLayout<SECURITY_ATTRIBUTES>.size)
        clientSecurityAttributes.lpSecurityDescriptor = nil
        clientSecurityAttributes.bInheritHandle = true
        printOSCall("CreateFileA", pipeName, clientAccess, 0, "ptr(\(clientSecurityAttributes))", "OPEN_EXISTING", 0, nil)
        let clientPipe = CreateFileA(
            /* lpFileName */ pipeName,
            /* dwDesiredAccess */ clientAccess,
            /* dwShareMode */ 0,
            /* lpSecurityAttributes */ &clientSecurityAttributes,
            /* dwCreationDisposition */ DWORD(OPEN_EXISTING),
            /* dwFlagsAndAttributes */ 0,
            /* hTemplateFile */ nil
        )
        guard clientPipe != INVALID_HANDLE_VALUE else {
            fatalError("Client pipe creation failed with error: \(WindowsSpawnImpl.Error(systemError: GetLastError()))")
        }

        printOSCall("ConnectNamedPipe", serverPipe, nil)
        guard ConnectNamedPipe(serverPipe, nil) || GetLastError() == ERROR_PIPE_CONNECTED else {
            fatalError("Pipe connection failed with error: \(WindowsSpawnImpl.Error(systemError: GetLastError()))")
        }

        printOSCall("_open_osfhandle", clientPipe, 0)
        let fileDescriptorForReading = FileDescriptor(_open_osfhandle(.init(bitPattern: clientPipe), _O_RDONLY))
        printOSCall("_open_osfhandle", serverPipe, 0)
        let fileDescriptorForWriting = FileDescriptor(_open_osfhandle(.init(bitPattern: serverPipe), _O_APPEND))
        fileHandleForReading = FDFileHandle(fileDescriptor: fileDescriptorForReading, closeOnDealloc: true)
        fileHandleForWriting = FDFileHandle(fileDescriptor: fileDescriptorForWriting, closeOnDealloc: true)

        #else
        let pipe = Pipe()
        fileHandleForReading = FDFileHandle(
            fd: FileDescriptor(pipe.fileHandleForReading), 
            handle: pipe.fileHandleForReading
        )
        fileHandleForWriting = FDFileHandle(
            fd: FileDescriptor(pipe.fileHandleForWriting), 
            handle: pipe.fileHandleForWriting
        )
        #endif
    }
}