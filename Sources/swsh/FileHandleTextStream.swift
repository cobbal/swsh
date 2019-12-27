import Foundation

/// A wrapper to convert a `FileHandle` into a `TextOutputStream`
public struct FileHandleTextStream: TextOutputStream {
    /// the underlying handle
    public let handle: FileHandle
    /// the encoding used to write to the handle
    public let encoding: String.Encoding

    /// Create a text stream that writes to the filehandle using the specified encoding
    public init(_ handle: FileHandle, encoding: String.Encoding = .utf8) {
        self.handle = handle
        self.encoding = encoding
    }

    public func write(_ string: String) {
        guard let data = string.data(using: .utf8) else { return }
        handle.write(data)
    }
}
