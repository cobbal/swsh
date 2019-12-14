import Foundation

public struct FileHandleTextStream: TextOutputStream {
    public let handle: FileHandle
    public let encoding: String.Encoding

    public init(_ handle: FileHandle, encoding: String.Encoding = .utf8) {
        self.handle = handle
        self.encoding = encoding
    }

    public func write(_ string: String) {
        guard let data = string.data(using: .utf8) else { return }
        handle.write(data)
    }
}
