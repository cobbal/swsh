import Foundation

/// A version of `FileHandle` that can be accessed by handle or fd at the same time
public class FDFileHandle {
    public let fileDescriptor: FileDescriptor
    public let handle: FileHandle
    private let close: ((FileHandle) -> Void)?

    public init(fileDescriptor: FileDescriptor, handle: FileHandle, closeBody: ((FileHandle) -> Void)? = nil) {
        self.fileDescriptor = fileDescriptor
        self.handle = handle
        self.close = closeBody
    }

    public convenience init(fileDescriptor: FileDescriptor) {
        // Construct the handle around the fd, but do not use closeOnDealloc, as this closes the fd!
        let handle = FileHandle(fileDescriptor: fileDescriptor.rawValue)
        let osHandle = _get_osfhandle(fileDescriptor.rawValue)
        precondition(osHandle != -1/*INVALID_HANDLE_VALUE*/ && osHandle != -2/*special Windows value*/)

        // Configure this to close on dealloc manually
        self.init(fileDescriptor: fileDescriptor, handle: handle)
    }

    deinit {
        if let close = close {
            close(self.handle)
        } else {
            handle.closeIgnoringErrors()
        }
    }
}
