@testable import swsh
import XCTest

class MockCommand: Command, Equatable {
    class Result: CommandResult {
        private var _command: MockCommand
        public var command: Command { _command }
        private var _exitCode: Int32?
        private var _exitSemaphore = DispatchSemaphore(value: 0)
        public var fdMap: FDMap
        public var handles: [Int32: FileHandle]

        public init(command: MockCommand, fdMap: FDMap) {
            _command = command
            self.fdMap = fdMap
            handles = [Int32: FileHandle]()
            for (src, dst) in fdMap {
                handles[dst] = handles[src] ?? FileHandle(fileDescriptor: dup(src), closeOnDealloc: true)
            }
        }

        subscript(_ fd: Int32) -> FileHandle! { return handles[fd] }

        public func setExit(code: Int32) {
            let old = _exitCode
            _exitCode = code
            if old == nil {
                _exitSemaphore.signal()
            }
        }

        public var isRunning: Bool { return _exitCode == nil }
        func exitCode() -> Int32 {
            _exitSemaphore.wait()
            _exitSemaphore.signal()
            return _exitCode!
        }

        func succeed() throws { try defaultSucceed() }

        func kill(signal: Int32) throws {
            if let error = _command.killResponse {
                throw error
            }
        }
    }

    public var killResponse: Error?
    var resultCallback: ((Result) -> Void)?

    func coreAsync(fdMap: FDMap) -> CommandResult {
        let result = Result(command: self, fdMap: fdMap)
        resultCallback?(result)
        return result
    }

    static func == (lhs: MockCommand, rhs: MockCommand) -> Bool { return lhs === rhs }
}
