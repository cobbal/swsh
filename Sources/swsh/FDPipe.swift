import Foundation

/// A version of `Pipe` that works more uniformly between windows and posix
public class FDPipe {
    public let fileHandleForReading: FDFileHandle
    public let fileHandleForWriting: FDFileHandle

    public init() {
        #if os(Windows)
        /// the `pipe` system call creates two `fd` in a malloc'ed area
        let fds = UnsafeMutablePointer<Int32>.allocate(capacity: 2)
        defer { fds.deallocate() }
        /// If the operating system prevents us from creating file handles, stop
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
        #else
        let pipe = Pipe()
        fileDescriptorForReading = FDFileHandle(
            fd: FileDescriptor(pipe.fileHandleForReading), 
            handle: pipe.fileHandleForReading
        )
        fileDescriptorForWriting = FDFileHandle(
            fd: FileDescriptor(pipe.fileHandleForWriting), 
            handle: pipe.fileHandleForWriting
        )
        #endif
    }
}