import Foundation

/// A version of `FileHandle` that can be accessed by handle or fd at the same time
public class FDFileHandle: CustomDebugStringConvertible {
    public let fileDescriptor: FileDescriptor
    public let handle: FileHandle
    private let closeOnDealloc: Bool
    private var isClosed: Bool
    
    public convenience init(fileDescriptor: FileDescriptor, closeOnDealloc: Bool) {
        // Construct the handle around the fd, but do not use closeOnDealloc, as this closes the fd!
        let handle = FileHandle(fileDescriptor: fileDescriptor.rawValue, closeOnDealloc: false)
        self.init(fileDescriptor: fileDescriptor, handle: handle, closeOnDealloc: closeOnDealloc)
    }
    
    public init(fileDescriptor: FileDescriptor, handle: FileHandle, closeOnDealloc: Bool) {
        self.fileDescriptor = fileDescriptor
        self.handle = handle
        self.closeOnDealloc = closeOnDealloc
        self.isClosed = false
        // print("Created FDFileHandle for \(debugDescription)")
    }

    public func close() {
        precondition(!isClosed)
        close_fd(fileDescriptor)
        isClosed = true
        // print("Closed FDFileHandle for \(debugDescription)")
    }

    public var debugDescription: String {
        return "fd: \(fileDescriptor.rawValue) handle: \(handle) closeOnDealloc: \(closeOnDealloc)"
    }

    deinit {
        if closeOnDealloc && !isClosed {
            close()
        }
    }
}

fileprivate func close_fd(_ fileDescriptor: FileDescriptor) {
    #if os(Windows)
    printOSCall("_close", fileDescriptor.rawValue)
    _close(fileDescriptor.rawValue)
    #else
    printOSCall("close", fileDescriptor.rawValue)
    close(fileDescriptor.rawValue)
    #endif
}