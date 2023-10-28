import Foundation

// A version of `Pipe` that works more uniformly between windows and posix
public class FDPipe {
    public let fileDescriptorForReading: FileDescriptor
    public let fileDescriptorForWriting: FileDescriptor
    public let fileHandleForReading: FileHandle
    public let fileHandleForWriting: FileHandle

    public init() {
        #if os(Windows)
        /// the `pipe` system call creates two `fd` in a malloc'ed area
        let fds = UnsafeMutablePointer<Int32>.allocate(capacity: 2)
        defer { fds.deallocate() }
        /// If the operating system prevents us from creating file handles, stop
        let ret = _pipe(fds, 0, _O_BINARY)
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

        fileHandleForReading = FileHandle(fileDescriptor: fileDescriptorForReading.rawValue, closeOnDealloc: true)
        fileHandleForWriting = FileHandle(fileDescriptor: fileDescriptorForWriting.rawValue, closeOnDealloc: true)
        #else
        let pipe = Pipe()
        fileHandleForReading = pipe.fileHandleForReading
        fileHandleForWriting = pipe.fileHandleForWriting
        fileDescriptorForReading = FileDescriptor(pipe.fileHandleForReading)
        fileDescriptorForWriting = FileDescriptor(pipe.fileHandleForWriting)
        #endif
    }
}