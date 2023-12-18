import Foundation

/// A version of `FileHandle` that can be accessed by handle or fd at the same time
public class FDFileHandle {
    public let fd: Int32
    public let handle: FileHandle

    public init(fd: Int32) {
        self.fd = fd
        // Construct the handle around the fd, but do not use closeOnDealloc, as this closes the fd!
        self.handle = FileHandle(fileDescriptor: fd)
    }
    deinit {
        // Close on dealloc
        // TODO: What if this errors? Need to do something more here?
        try? handle.close()
    }
}
