import Foundation

/// A version of `FileHandle` that can be accessed by handle or fd at the same time
public class FDFileHandle {
    public let fileDescriptor: FileDescriptor
    public let handle: FileHandle
    private let closeOnDealloc: Bool
    private var isClosed: Bool
    
    public init(fileDescriptor: FileDescriptor, handle: FileHandle, closeOnDealloc: Bool) {
        self.fileDescriptor = fileDescriptor
        self.handle = handle
        self.closeOnDealloc = closeOnDealloc
        self.isClosed = false
    }

    public convenience init(fileDescriptor: FileDescriptor, closeOnDealloc: Bool) {
        // Construct the handle around the fd, but do not use closeOnDealloc, as this closes the fd!
        let handle = FileHandle(fileDescriptor: fileDescriptor.rawValue)
        let osHandle = _get_osfhandle(fileDescriptor.rawValue)
        precondition(osHandle != -1/*INVALID_HANDLE_VALUE*/ && osHandle != -2/*special Windows value*/)

        // Configure this to close on dealloc manually
        self.init(fileDescriptor: fileDescriptor, handle: handle, closeOnDealloc: closeOnDealloc)
    }

    // public convenience init(fileDescriptor: FileDescriptor) {
    //     self.init(fileDescriptor: fileDescriptor, closeOnDealloc: false)
    // }

    public func close() {
        precondition(!isClosed)

        print("Closing \(fileDescriptor.rawValue) handle: \(handle)...")
        _close(fileDescriptor.rawValue)
        isClosed = true
    }

    deinit {
        if closeOnDealloc && !isClosed {
            close()
        }
    }
}
