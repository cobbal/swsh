@testable import swsh
import XCTest

class CommandExtensionTests: XCTestCase {
    let cmd = MockCommand()

    var str = "hello\n"
    var data: Data { str.data(using: .utf8)! }

    func withResult<T>(_ cmd: MockCommand, block: () -> T) -> (MockCommand.Result, T) {
        var result: MockCommand.Result?
        cmd.resultCallback = { result = $0 }
        let blockResult = block()
        cmd.resultCallback = nil
        return (result!, blockResult)
    }

    func withAsyncResult(
        _ cmd: MockCommand,
        _ runnerBlock: @escaping (MockCommand) throws -> Void,
        _ resultBlock: @escaping (MockCommand.Result) -> Void
    ) {
        let finish = XCTestExpectation()

        cmd.resultCallback = {
            resultBlock($0)
        }
        DispatchQueue.global().async {
            try! XCTAssertNoThrow(runnerBlock(cmd))
            finish.fulfill()
        }
        wait(for: [finish], timeout: 1)
        cmd.resultCallback = nil
    }

    func withAsyncEcho(
        _ cmd: MockCommand,
        fds: [FileDescriptor] = [.stdout],
        block: @escaping (MockCommand) throws -> Void
    ) {
        withAsyncResult(cmd, block) { res in
            for fd in fds {
                res[fd].write(self.data)
                res[fd].closeFile()
            }
            res.setExit(code: 0)
        }
    }

    func testAsync() throws {
        #if os(Windows)
        XCTFail("Succeeds on Windows from PowerShell, but fails from VSCode. Why?")
        #else
        let res = try unwrap(cmd.async(stdin: 4, stdout: 5, stderr: 6) as? MockCommand.Result)
        XCTAssertEqual(res.fdMap, [0: 4, 1: 5, 2: 6])
        #endif
    }

    func testAsyncStream() {
        #if os(Windows)
        XCTFail("Why does FileHandle raise error 512 here on Windows?")
        #else
        let (res, handle) = withResult(cmd) { cmd.asyncStream() }
        res[1].write(data)
        res[2].write(data)
        res[1].closeFile()
        res[2].closeFile()
        XCTAssertEqual(handle.handle.readDataToEndOfFile(), data)
        #endif
    }

    func testRunSucceeds() {
        withAsyncResult(cmd, {
            try $0.run()
        }, { res in
            res.setExit(code: 0)
        })
    }

    func testRunBoolTrue() {
        withAsyncResult(cmd, {
            XCTAssertTrue($0.runBool())
        }, { res in
            res.setExit(code: 0)
        })
    }

    func testRunBoolFalse() {
        withAsyncResult(cmd, {
            XCTAssertFalse($0.runBool())
        }, { res in
            res.setExit(code: 42)
        })
    }

    func testRunFile() {
        withAsyncEcho(cmd) {
            let url = try $0.runFile()
            XCTAssertEqual(try Data(contentsOf: url), self.data)
        }
    }

    func testRunData() {
        withAsyncEcho(cmd) {
            XCTAssertEqual(try $0.runData(), self.data)
        }
    }

    func testRunString() {
        withAsyncEcho(cmd) {
            XCTAssertEqual(try $0.runString(), "hello")
        }
    }

    func testRunStringBlank() {
        str = "\n\n"
        withAsyncEcho(cmd) {
            XCTAssertEqual(try $0.runString(), "")
        }
    }

    func testRunStringBadEncoding() {
        str = "Ünicode"
        withAsyncEcho(cmd) {
            XCTAssertThrowsError(try $0.runString(encoding: .nonLossyASCII))
        }
    }

    func testRunLines() {
        str = "a\nb\n\nc\n\n"
        withAsyncEcho(cmd) {
            XCTAssertEqual(try $0.runLines(), ["a", "b", "", "c"])
        }
    }

    func testRunJSON() {
        str = "{\"x\": [1, 2]}"
        withAsyncEcho(cmd) {
            XCTAssertEqual(try $0.runJSON() as? [String: [Int]], ["x": [1, 2]])
        }
    }

    func testInvalidJSON() {
        withAsyncEcho(cmd) {
            XCTAssertThrowsError(try $0.runJSON())
        }
    }

    func testJSONDecodable() {
        str = "{\"x\": [1, 2]}"
        withAsyncEcho(cmd) {
            XCTAssertEqual(try $0.runJSON([String: [Int]].self), ["x": [1, 2]])
        }
    }

    func testInvalidJSONDecodable() {
        withAsyncEcho(cmd) {
            XCTAssertThrowsError(try $0.runJSON(Int.self))
        }
    }
}
