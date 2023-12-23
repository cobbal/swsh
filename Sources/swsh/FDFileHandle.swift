import Foundation

/// A version of `FileHandle` that can be accessed by handle or fd at the same time
public class FDFileHandle: CustomDebugStringConvertible {
    public let fileDescriptor: FileDescriptor
    private let osHandle: intptr_t
    public let handle: FileHandle
    private let closeOnDealloc: Bool
    private var isClosed: Bool
    
    public convenience init(fileDescriptor: FileDescriptor, closeOnDealloc: Bool) {
        // Construct the handle around the fd, but do not use closeOnDealloc, as this closes the fd!
        let handle = FileHandle(fileDescriptor: fileDescriptor.rawValue, closeOnDealloc: false)
        self.init(handle: handle, closeOnDealloc: closeOnDealloc)
    }
    
    public init(handle: FileHandle, closeOnDealloc: Bool) {
        #if os(Windows)
        printOSCall("_get_osfhandle", fileDescriptor.rawValue)
        let osHandle = _get_osfhandle(fileDescriptor.rawValue)
        precondition(osHandle != -1/*INVALID_HANDLE_VALUE*/ && osHandle != -2/*special Windows value*/)
        #else
        // TODO: OS handle for macOS / Linux?
        let osHandle = 0
        #endif

        self.fileDescriptor = FileDescriptor(handle.fileDescriptor)
        self.osHandle = osHandle
        self.handle = handle
        self.closeOnDealloc = closeOnDealloc
        self.isClosed = false
        // print("Created FDFileHandle for \(debugDescription)")
    }

    public func close() {
        precondition(!isClosed)
        #if os(Windows)
        printOSCall("_close", fileDescriptor.rawValue)
        _close(fileDescriptor.rawValue)
        #else
        printOSCall("close", fileDescriptor.rawValue)
        Darwin.close(fileDescriptor.rawValue)
        #endif
        isClosed = true
        // print("Closed FDFileHandle for \(debugDescription)")
    }

    public var debugDescription: String {
        return "fd: \(fileDescriptor.rawValue) osHandle: \(UnsafeRawPointer(bitPattern: osHandle).map { $0.debugDescription } ?? "0x0000000000000000") fileHandle: \(handle) closeOnDealloc: \(closeOnDealloc)"
    }

    deinit {
        if closeOnDealloc && !isClosed {
            close()
        }
    }
}
