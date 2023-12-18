import Foundation

/// A version of `Pipe` that works more uniformly between windows and posix
public class FDPipe {
    private let readingSide: FDFileHandle
    private let writingSide: FDFileHandle

    public var fileDescriptorForReading: FileDescriptor { readingSide.fileDescriptor }
    public var fileDescriptorForWriting: FileDescriptor { writingSide.fileDescriptor }
    public var fileHandleForReading: FileHandle { readingSide.handle }
    public var fileHandleForWriting: FileHandle { writingSide.handle }

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

        readingSide = FDFileHandle(fileDescriptor: fileDescriptorForReading)
        writingSide = FDFileHandle(fileDescriptor: fileDescriptorForWriting)
        print("pipe.fileDescriptorForReading \(fileDescriptorForReading)")
        print("pipe.fileDescriptorForWriting \(fileDescriptorForWriting)")
        #else
        let pipe = Pipe()
        readingSide = FDFileHandle(
            fd: FileDescriptor(pipe.fileHandleForReading), 
            handle: pipe.fileHandleForReading
        )
        writingSide = FDFileHandle(
            fd: FileDescriptor(pipe.fileHandleForWriting), 
            handle: pipe.fileHandleForWriting
        )
        #endif
    }
}