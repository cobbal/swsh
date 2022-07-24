@testable import swsh
import XCTest

class AsyncMockCommand: MockCommand {
    class AsyncResult: MockCommand.Result, AsyncCommandResult {
        func asyncFinish() async {
            // Not a good idea outside of a test, as one thread will be blocked until this finishes
            _ = await Task {
                withSyncContext { finish() }
            }.result
        }
    }

    override func coreAsync(fdMap: FDMap) -> CommandResult {
        let result = AsyncResult(command: self, fdMap: fdMap)
        resultCallback?(result)
        return result
    }
}
