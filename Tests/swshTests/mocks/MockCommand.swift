@testable import swsh
import XCTest

class MockCommand: Command, Equatable {
    class Result: CommandResult, Equatable {
        public var command: Command
        private var _exitCode: Int32?
        private var _exitSemaphore = DispatchSemaphore(value: 0)
        public var fdMap: FDMap

        public init(command: Command, fdMap: FDMap) {
            self.command = command
            self.fdMap = fdMap
        }

        public func setExit(code: Int32) {
            let old = _exitCode
            _exitCode = code
            if old == nil {
                _exitSemaphore.signal()
            }
        }

        public var isRunning: Bool { _exitCode == nil }
        func exitCode() -> Int32 {
            _exitSemaphore.wait()
            _exitSemaphore.signal()
            return _exitCode!
        }

        func succeed() throws { try defaultSucceed() }

        static func == (lhs: Result, rhs: Result) -> Bool { lhs === rhs }
    }

    func coreAsync(fdMap: FDMap) -> CommandResult {
        return Result(command: self, fdMap: fdMap)
    }

    static func == (lhs: MockCommand, rhs: MockCommand) -> Bool { lhs === rhs }
}
