@testable import swsh
import XCTest

class CommandConcurrencyTests: XCTestCase {
    // MARK: Utilities

    func sync<R>(body: @escaping () async throws -> R) throws -> R {
        // Expectations in async tests are currently broken on linux, so we need a way to force an async environment
        let semaphore = DispatchSemaphore(value: 0)
        let result = UnsafeMutablePointer<Result<R, Error>?>.allocate(capacity: 1)
        result.initialize(to: nil)
        defer {
            result.deinitialize(count: 1)
            result.deallocate()
        }
        Task {
            do {
                result.pointee = try await .success(body())
            } catch let e {
                result.pointee = .failure(e)
            }
            semaphore.signal()
        }
        semaphore.wait()
        return try result.pointee!.get()
    }

    let commandAndResult: (command: AsyncMockCommand, result: Task<AsyncMockCommand.Result, Never>) = {
        let command = AsyncMockCommand()
        return (
            command,
            Task {
                await withCheckedContinuation { kont in
                    command.resultCallback = {
                        command.resultCallback = nil
                        kont.resume(returning: $0)
                    }
                }
            }
        )
    }()

    func result() async -> AsyncMockCommand.Result {
        await commandAndResult.result.value
    }
    var command: AsyncMockCommand { commandAndResult.command }

    var str = "hello\n"
    var data: Data { str.data(using: .utf8)! }
    func echo(fds: [FileDescriptor] = [.stdout]) async {
        let res = await result()
        for fd in fds {
            res[fd].write(self.data)
            res[fd].closeFile()
        }
        res.setExit(code: 0)
    }

    // MARK: Tests

    func testAsyncRunSucceedsAsynchronously() throws {
        let finished = expectation(description: "run not finished")
        finished.isInverted = true

        let task = Task {
            try await command.run()
            finished.fulfill()
        }

        wait(for: [finished], timeout: 0.1)
        try sync {
            await self.result().setExit(code: 0)
            try await task.result.get()
        }
    }

    func testAsyncRunFails() throws {
        let notFinished = expectation(description: "run not finished")
        notFinished.isInverted = true

        let task = Task {
            try await self.command.run()
            notFinished.fulfill()
        }

        Thread.sleep(forTimeInterval: 0.1)
        try sync {
            await self.result().setExit(code: 1)
            await self.XCTAssertThrowsAsyncError(try await task.result.get()) { error in
                if let error = error as? ExitCodeFailure {
                    XCTAssertEqual(error.exitCode, 1)
                } else {
                    XCTFail("Expected ExitCodeFailure, got \(error)")
                }
            }
        }
        wait(for: [notFinished], timeout: 0.1)
    }

    func testAsyncRunSucceedsWithNonAsyncAwareCommand() throws {
        let command = MockCommand()
        var result: MockCommand.Result?
        command.resultCallback = { result = $0 }

        let finished = expectation(description: "run not finished")
        finished.isInverted = true

        let task = Task {
            try await command.run()
            finished.fulfill()
        }

        wait(for: [finished], timeout: 0.1)
        try unwrap(result).setExit(code: 0)
        try sync {
            try await task.result.get()
        }
    }

    func testAsyncFinishSucceeds() throws {
        let task = Task {
            await command.async().finish()
        }
        Thread.sleep(forTimeInterval: 0.1)
        try sync {
            await self.result().setExit(code: 1)
            _ = try await task.result.get()
        }
    }

    func testRunFile() throws {
        Task { await echo() }
        let url = try sync {
            try await self.command.runFile()
        }
        XCTAssertEqual(try Data(contentsOf: url), data)
    }

    func testRunStringBlank() throws {
        str = "\n\n"
        Task { await echo() }
        let result = try sync {
            try await self.command.runString()
        }
        XCTAssertEqual(result, "")
    }

    func testRunStringBadEncoding() throws {
        str = "Ünicode"
        Task { await echo() }
        try sync {
            await self.XCTAssertThrowsAsyncError(try await self.command.runString(encoding: .nonLossyASCII))
        }
    }

    func testRunLines() throws {
        str = "a\nb\n\nc\n\n"
        Task { await echo() }
        let result = try sync { try await self.command.runLines() }
        XCTAssertEqual(result, ["a", "b", "", "c"])
    }

    func testRunJSON() throws {
        str = "{\"x\": [1, 2]}"
        Task { await echo() }
        let result = try sync { try await self.command.runJSON() }
        XCTAssertEqual(result as? [String: [Int]], ["x": [1, 2]])
    }

    func testInvalidJSON() throws {
        Task { await echo() }
        try sync {
            await self.XCTAssertThrowsAsyncError(try await self.command.runJSON())
        }
    }

    func testJSONDecodable() throws {
        str = "{\"x\": [1, 2]}"
        Task { await echo() }
        let result = try sync { try await self.command.runJSON([String: [Int]].self) }
        XCTAssertEqual(result, ["x": [1, 2]])
    }

    func testInvalidJSONDecodable() throws {
        Task { await echo() }
        try sync {
            await self.XCTAssertThrowsAsyncError(try await self.command.runJSON(Int.self))
        }
    }
}
